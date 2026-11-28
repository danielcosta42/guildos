----------------------------------------------------------------------
-- Guild OS - Allies on the world map, by zone (site spec 123, issue #449)
--
-- The alliance's guilds see each other on the world map, only in the SAME ZONE, when the leader turned the map on
-- for them on guildos.me (GOSGILD1.alliance.share.map, read by AllianceLink:Shares):
--   * SENDING (map.send): each client says its own position on the alliance's hidden channel (AllianceLink), as an
--     addon message through ChatThrottleLib (Compat.SendAddonMessage, "BULK"), at a LOW pace: at most every
--     MOVE_MIN seconds while it moves, every STILL_MAX seconds when it does not. Only the zone's map and the
--     coordinates on it go, nothing else. Never in an instance (in combat or not), never in a chat lockdown,
--     never when the player turned off "Share my position with the guild" (GuildMap:IsSharing, the same switch as
--     the guild's map), never while the server said "too fast" lately (the channel's throttle, AllianceLink:
--     Throttled, or the whisper queue's backoff, WhisperQueue:Interval), never where /gos probe channel measured
--     a channel addon message from a timer refused. Stopping to share (the switch, map.send off, an instance)
--     sends one retraction, so the pin goes at once.
--   * RECEIVING (map.recv and "Show guildmates on my map", GuildMap:IsShowingOthers): a line from the channel,
--     its guild named as the chat's are (AllianceLink:GuildOfLine: never our own guild, never a blocked one), is
--     kept only when its zone is the zone this client is in, and drawn only while it still is; never in an
--     instance. The world map draws them in their own style (UI/GuildMap.lua: the guild's colour and initials);
--     never the minimap, and never in GuildMap's own tables: the guild's positions stay exactly as they were.
--
-- The line: "1,<code>,<mapID>,<x>,<y>" with code the sender's guild's three characters (AllianceLink.Code), mapID
-- the zone's map, x and y whole numbers 0..9999 (ten-thousandths of the map). "1,<code>,-" is a retraction. Every
-- field is checked on receipt and the coordinates clamped; anything else is dropped. A sender heard more often
-- than SENDER_GAP is dropped too. Identity is the channel's sender, never the payload.
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
local AM = {}
GuildOS.AllianceMap = AM

AM.PREFIX     = "GuildOSAllyMap"   -- 14 bytes, under the game's 16
AM.PROTO      = "1"
AM.MOVE_MIN   = 15        -- seconds: at most this often while moving
AM.STILL_MAX  = 60        -- and this often when still
AM.MOVE_EPS   = 0.003     -- of the zone's width: under this the player "did not move"
AM.TICK       = 3         -- seconds between two looks at whether a position is owed
AM.FADE       = 75        -- an ally's pin starts fading this long after its last line (a still one sends every 60 s)
AM.GONE       = 150       -- and is gone after this
AM.SENDER_GAP = 10        -- seconds: lines from one sender closer than this are dropped (nobody honest sends them)
AM.MAX_ALLIES = 200       -- allies kept at most
AM.LINE_MAX   = 40        -- bytes of a line

AM.allies = {}            -- [sender] = { key, name, guild, mapID, x, y, t }
AM.sent = nil             -- what this client last sent: { t, mapID, x, y }
AM.stats = { sent = 0, received = 0, dropped = 0, retracted = 0 }

local floor = math.floor
local function now() return GetTime() end
local function link() return GuildOS.AllianceLink end
local function GM() return GuildOS.GuildMap end

----------------------------------------------------------------------
-- Pure: the wire (tools/alliance-map.lua)
----------------------------------------------------------------------
local function clamp01(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- The line for a position, or for a retraction (pos nil). nil when the code or the position is not one.
function AM.Encode(code, pos)
    if type(code) ~= "string" or not code:match("^%w%w%w$") then return nil end
    if pos == nil then return AM.PROTO .. "," .. code .. ",-" end
    local map, x, y = tonumber(pos.mapID), clamp01(pos.x), clamp01(pos.y)
    if not map or map ~= floor(map) or map <= 0 or map > 1000000 or not x or not y then return nil end
    return string.format("%s,%s,%d,%d,%d", AM.PROTO, code, map, floor(x * 9999 + 0.5), floor(y * 9999 + 0.5))
end

-- A line back to { code, mapID, x, y } or { code, retract = true }; nil for anything malformed.
function AM.Decode(s)
    if type(s) ~= "string" or #s > AM.LINE_MAX then return nil end
    local code = s:match("^1,(%w%w%w),%-$")
    if code then return { code = code, retract = true } end
    local m, xs, ys
    code, m, xs, ys = s:match("^1,(%w%w%w),(%d%d?%d?%d?%d?%d?%d?),(%d%d?%d?%d?%d?),(%d%d?%d?%d?%d?)$")
    if not code then return nil end
    local map = tonumber(m)
    if not map or map <= 0 or map > 1000000 then return nil end
    return { code = code, mapID = map, x = clamp01(tonumber(xs) / 9999), y = clamp01(tonumber(ys) / 9999) }
end

-- Pure. Whether a position goes now: never more often than MOVE_MIN; then when it moved (or changed zone), and in
-- any case after STILL_MAX.
function AM.ShouldSend(last, pos, t)
    if not pos then return false end
    if not last then return true end
    local el = t - last.t
    if el < AM.MOVE_MIN then return false end
    if el >= AM.STILL_MAX or pos.mapID ~= last.mapID then return true end
    local dx, dy = pos.x - last.x, pos.y - last.y
    return dx * dx + dy * dy >= AM.MOVE_EPS * AM.MOVE_EPS
end

----------------------------------------------------------------------
-- This client
----------------------------------------------------------------------
-- The zone the player is in (the zone's map, GuildMap:_ZoneOf), or nil: in an instance, or no map.
function AM:MyZone()
    local Compat = GuildOS.Compat
    if Compat.InstanceState() then return nil end
    local map = Compat.GetBestMapForUnit("player")
    if type(map) ~= "number" or map <= 0 then return nil end
    return GM():_ZoneOf(map), map
end

-- This client's position as it may go on the alliance channel, or nil and why not: "off" (no alliance, the map
-- not sent by this guild, or the player does not share), "instance", "locked" (chat lockdown), "nomap".
function AM:_ReadSelf()
    local L, G = link(), GM()
    if not (L and G and L:Active() and L:Shares("map", "send") and G:IsSharing()) then return nil, "off" end
    local Compat = GuildOS.Compat
    if Compat.InstanceState() then return nil, "instance" end
    if Compat.InChatLockdown and Compat.InChatLockdown() then return nil, "locked" end
    local zone, map = self:MyZone()
    if not zone then return nil, "nomap" end
    local x, y = Compat.GetPlayerMapPosition(zone, "player")
    if not x and map ~= zone then
        zone = map
        x, y = Compat.GetPlayerMapPosition(map, "player")
    end
    if not x or not y then return nil, "nomap" end
    return { mapID = zone, x = x, y = y }
end

-- The channel's number when a line may go on it now, or nil: joined, the server not saying "too fast" lately (the
-- channel's notice, or the whisper queue's backoff after ERR_GENERIC_THROTTLE), and the probe not having measured
-- a channel addon message from a timer refused here.
function AM:_Channel()
    local L = link()
    local index = L and L:ChannelIndex()
    if not index then return nil end
    if L.Throttled and L:Throttled() then return nil end
    local Q = GuildOS.WhisperQueue
    if Q and Q.Interval and Q.INTERVAL and Q:Interval() > Q.INTERVAL then return nil end
    local probe = type(GuildOSDB) == "table" and GuildOSDB.probeChannel
    if type(probe) == "table" and probe.timer == false then return nil end
    return index
end

function AM:_Say(line)
    local index = self:_Channel()
    if not index or not line then return false end
    GuildOS.Compat.SendAddonMessage(self.PREFIX, line, "CHANNEL", index, "BULK")
    return true
end

-- Every TICK seconds: a position when one is owed, a retraction once when sharing stops.
function AM:Tick(t)
    t = t or now()
    self:_Prune(t)
    local pos, why = self:_ReadSelf()
    local L = link()
    local mine = GuildOS.Alliance and GuildOS.Alliance:MyGuildName()
    local code = mine and L and L.Code(mine)
    if not pos then
        -- Stopped sharing (the switch, the leader's, an instance): one retraction, so allies' pins go at once.
        if self.sent and (why == "off" or why == "instance") then
            if code and self:_Say(AM.Encode(code, nil)) then self.stats.retracted = self.stats.retracted + 1 end
            self.sent = nil
        end
        return false
    end
    if not code or not AM.ShouldSend(self.sent, pos, t) then return false end
    if not self:_Say(AM.Encode(code, pos)) then return false end
    self.sent = { t = t, mapID = pos.mapID, x = pos.x, y = pos.y }
    self.stats.sent = self.stats.sent + 1
    return true
end

----------------------------------------------------------------------
-- Receiving
----------------------------------------------------------------------
-- Whether this client draws allies now: the alliance in force, this guild receives the map, the player shows
-- guildmates on their map.
function AM:Receiving()
    local L, G = link(), GM()
    return L ~= nil and G ~= nil and L:Active() and L:Shares("map", "recv") and G:IsShowingOthers()
end

-- A line from the alliance channel (CHAT_MSG_ADDON on our prefix, from the channel in force). `sender` is the
-- channel's, which nobody can forge.
function AM:HandleLine(sender, text)
    local L = link()
    if type(sender) ~= "string" or sender == "" or not L or L.IsMe(sender) then return false end
    local p = AM.Decode(text)
    if not p then self.stats.dropped = self.stats.dropped + 1; return false end
    if not self:Receiving() then return false end
    local guild = L:GuildOfLine(p.code, sender, "M", nil)
    if not guild then self.stats.dropped = self.stats.dropped + 1; return false end
    local t = now()
    if p.retract then
        self.allies[sender] = nil
        self:_Refresh()
        return true
    end
    local old = self.allies[sender]
    if old and t - old.t < AM.SENDER_GAP then self.stats.dropped = self.stats.dropped + 1; return false end
    -- Only the zone this client is in: anything else is not kept at all.
    local zone = self:MyZone()
    if not zone or GM():_ZoneOf(p.mapID) ~= zone then
        if old then self.allies[sender] = nil; self:_Refresh() end
        return false
    end
    if not old then
        local n = 0
        for _ in pairs(self.allies) do n = n + 1 end
        if n >= AM.MAX_ALLIES then self.stats.dropped = self.stats.dropped + 1; return false end
    end
    local name = L.Speaker(sender)
    local info = GuildOS.Alliance and GuildOS.Alliance.MemberInfo and GuildOS.Alliance:MemberInfo(name)
    self.allies[sender] = { key = "ally:" .. sender, name = name, guild = guild, mapID = p.mapID, x = p.x, y = p.y,
                            t = t, class = info and info.class, level = info and info.level, ally = true }
    self.stats.received = self.stats.received + 1
    self:_Refresh()
    return true
end

function AM:_Prune(t)
    for k, a in pairs(self.allies) do
        if t - a.t > AM.GONE then self.allies[k] = nil end
    end
end

function AM:_Refresh()
    local G = GM()
    if G and G.uiRefresh then G.uiRefresh() end
end

-- fn(a, x, y, alpha) for every ally drawn at time t: only while this client receives, outside an instance, and
-- only those in the zone it is in now. For the WORLD MAP only (UI/GuildMap.lua); the minimap never asks.
function AM:ForEachAlly(t, fn)
    if not next(self.allies) or not self:Receiving() then return end
    local zone = self:MyZone()
    if not zone then return end
    local G = GM()
    for _, a in pairs(self.allies) do
        local age = t - a.t
        if age <= AM.GONE and G:_ZoneOf(a.mapID) == zone then
            fn(a, a.x, a.y, G:_StaleAlpha(age, AM.FADE, AM.GONE))
        end
    end
end

-- The allies drawn now, sorted by guild then name: { key, name, guild, class, level, mapID, x, y, alpha, age }.
function AM:GetAllies(t)
    t = t or now()
    local out = {}
    self:ForEachAlly(t, function(a, x, y, alpha)
        out[#out + 1] = { key = a.key, name = a.name, guild = a.guild, class = a.class, level = a.level,
                          mapID = a.mapID, x = x, y = y, alpha = alpha, age = t - a.t, ally = true,
                          zone = GM():_MapName(a.mapID) }
    end)
    table.sort(out, function(a, b)
        if a.guild ~= b.guild then return a.guild < b.guild end
        return a.name:lower() < b.name:lower()
    end)
    return out
end

-- Pure. The tag a pin carries: the guild's initials, up to three (letters and digits, the first of each word).
function AM.GuildTag(guild)
    local out = {}
    for word in tostring(guild or ""):gmatch("[^%s%-']+") do
        local c = word:match("^[%z\1-\127\194-\244][\128-\191]*")
        if c and c:match("^[%w\128-\255]") then out[#out + 1] = c:upper() end
        if #out >= 3 then break end
    end
    if #out == 0 then return "?" end
    return table.concat(out)
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function AM:Initialize()
    pcall(GuildOS.Compat.RegisterAddonPrefix, self.PREFIX)
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, text, channel, sender, target, _, localID, channelName)
        if prefix ~= AM.PREFIX or channel ~= "CHANNEL" then return end
        if GuildOS.Compat.IsSecret(text, sender, target, localID, channelName) then return end
        GuildOS:SafeCall(function()
            local L = link()
            -- Only the alliance's own channel: by its number, or its name as the client hands it.
            local index = L and L:ChannelIndex()
            local name = L and L:ChannelName()
            local base = type(channelName) == "string" and channelName ~= "" and channelName
                or (type(target) == "string" and (target:match("^%d+%.%s*(.+)$") or target)) or nil
            local ours = (index ~= nil and localID == index) or (name ~= nil and base ~= nil and base:lower() == name:lower())
            if ours then AM:HandleLine(sender, text) end
        end)
    end)
    self._frame = f
    self._ticker = GuildOS.Compat.NewTicker(AM.TICK, function() GuildOS:SafeCall(AM.Tick, AM) end)
end
