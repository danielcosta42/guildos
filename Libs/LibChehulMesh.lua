-- LibChehulMesh - shared mesh transport for the Chehul addon family
-- (PartyLens, ProfessionHelper, GuildOS). SHIP THIS FILE IDENTICAL in each addon.
--
-- A single instance lives at _G.ChehulMesh: whichever addon loads first creates it,
-- the rest reuse it. Every send is instrumented (ChehulMesh:Stats) so a dead mesh
-- can never fail silently again.
--
-- BUSES (transport reality on this client, measured — CHANNEL addon messages are
-- BLOCKED, so realm-wide can only ride a visible channel post):
--   Hidden, automatic (work from timers):
--     :Guild(prefix,payload) :Group(...) :Proximity(...) :Whisper(...,target)
--   Realm-wide (same faction), on the user's next click (SendChatMessage to a
--   channel is hardware-gated here), over a DEDICATED custom channel that only
--   addon users join (no spam to non-users) and which is filtered from chat:
--     :Realm(prefix, payload [, coalesceKey])
--
-- RECEIVE: :Register(prefix, handler) - handler(payload, sender, dist) fires for
-- both hidden addon messages and realm-wide channel posts of that prefix.

local VERSION = 1
if _G.ChehulMesh and (_G.ChehulMesh.version or 0) >= VERSION then
    return
end

local M = _G.ChehulMesh or {}
_G.ChehulMesh = M
M.version = VERSION

M.CHANNEL   = "ChehulMesh" -- dedicated realm-wide custom channel (addon users only)
M.FLUSH_GAP = 1.5          -- min seconds between realm-wide channel sends

M.handlers = M.handlers or {}  -- [prefix] = function(payload, sender, dist)
M.stats = M.stats or {
    sent = 0, ok = 0, throttled = 0, failed = 0,
    chanQueued = 0, chanSent = 0, recv = 0,
}

local function RecordSend(r)
    M.stats.sent = M.stats.sent + 1
    if type(r) == "number" then
        if r == 0 then M.stats.ok = M.stats.ok + 1; return true end
        if r == 3 or r == 8 then M.stats.throttled = M.stats.throttled + 1 else M.stats.failed = M.stats.failed + 1 end
        return false
    end
    if r ~= false and r ~= nil then M.stats.ok = M.stats.ok + 1; return true end
    M.stats.failed = M.stats.failed + 1
    return false
end

-- ---------------------------------------------------------------------------
-- Prefix registration + receive routing
-- ---------------------------------------------------------------------------
local registered = M._registered or {}
M._registered = registered

local function RegisterPrefix(prefix)
    if registered[prefix] then return end
    registered[prefix] = true
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then pcall(reg, prefix) end
end

-- Register a receive handler for a prefix (and enable its addon-message delivery).
function M:Register(prefix, handler)
    if type(prefix) ~= "string" or prefix == "" or type(handler) ~= "function" then
        return
    end
    M.handlers[prefix] = handler
    RegisterPrefix(prefix)
end

local function Dispatch(prefix, payload, sender, dist)
    local fn = M.handlers[prefix]
    if fn then
        M.stats.recv = M.stats.recv + 1
        pcall(fn, payload, sender, dist)
    end
end

-- ---------------------------------------------------------------------------
-- Hidden addon-message buses (automatic; deliver from timers)
-- ---------------------------------------------------------------------------
local function SendAddon(prefix, payload, dist, target)
    local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
    if not fn then M.stats.failed = M.stats.failed + 1; return false end
    RegisterPrefix(prefix)
    local ok, r = pcall(fn, prefix, payload, dist, target)
    if not ok then M.stats.failed = M.stats.failed + 1; return false end
    return RecordSend(r)
end
M.SendAddon = SendAddon

function M:Guild(prefix, payload)
    if IsInGuild and not IsInGuild() then return false end
    return SendAddon(prefix, payload, "GUILD")
end

function M:Group(prefix, payload)
    if IsInGroup and not IsInGroup() then return false end
    return SendAddon(prefix, payload, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
end

function M:Proximity(prefix, payload)
    return SendAddon(prefix, payload, "SAY")
end

function M:Whisper(prefix, payload, target)
    if not target or target == "" then return false end
    return SendAddon(prefix, payload, "WHISPER", target)
end

-- ---------------------------------------------------------------------------
-- Realm-wide bus: a visible post on a DEDICATED custom channel (addon users
-- only), hardware-gated so it flushes on the user's next click.
-- ---------------------------------------------------------------------------
local channelQueue = M._channelQueue or {}
M._channelQueue = channelQueue
local lastFlush = 0

local function ChannelNumber()
    local n = GetChannelName and GetChannelName(M.CHANNEL)
    return (type(n) == "number" and n > 0) and n or nil
end

-- Queue a realm-wide post; sent on the next click. Coalesced by key.
function M:Realm(prefix, payload, coalesceKey)
    if type(prefix) ~= "string" or type(payload) ~= "string" then return end
    RegisterPrefix(prefix)
    channelQueue[coalesceKey or (prefix .. ":" .. payload)] = prefix .. " " .. payload
    M.stats.chanQueued = M.stats.chanQueued + 1
end

local function FlushChannel()
    local key = next(channelQueue)
    if not key then return end
    if (GetTime() - lastFlush) < M.FLUSH_GAP then return end
    local num = ChannelNumber()
    if not num then return end -- not joined yet; retry on the next click
    local text = channelQueue[key]
    channelQueue[key] = nil
    lastFlush = GetTime()
    local ok = pcall(SendChatMessage, text, "CHANNEL", nil, num)
    if ok then M.stats.chanSent = M.stats.chanSent + 1 else M.stats.failed = M.stats.failed + 1 end
end

local function EnsureChannel()
    if not ChannelNumber() and JoinPermanentChannel then
        JoinPermanentChannel(M.CHANNEL)
    end
end

-- ---------------------------------------------------------------------------
-- Bootstrap: event frame, channel join, chat filter, hardware flush hook.
-- ---------------------------------------------------------------------------
local function OnAddonMsg(prefix, text, dist, sender)
    if prefix and M.handlers[prefix] and sender then
        Dispatch(prefix, text, sender, dist)
    end
end

-- Realm-wide channel receive: "<prefix>\009<payload>" on the ChehulMesh channel.
local function OnChannelMsg(text, sender, channelString)
    if not text or not sender then return end
    if not (channelString and channelString:lower():find("chehulmesh", 1, true)) then return end
    -- Wire format: "<prefix> <payload>" (prefix has no spaces; payload may).
    local prefix, payload = text:match("^(%S+)%s(.+)$")
    if prefix and M.handlers[prefix] then
        Dispatch(prefix, payload, sender, "REALM")
    end
end

if not M._booted then
    M._booted = true

    M.frame = CreateFrame("Frame")
    M.frame:RegisterEvent("CHAT_MSG_ADDON")
    M.frame:RegisterEvent("CHAT_MSG_CHANNEL")
    M.frame:RegisterEvent("PLAYER_LOGIN")
    M.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    M.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            OnAddonMsg(...)
        elseif event == "CHAT_MSG_CHANNEL" then
            local text, sender = ...
            OnChannelMsg(text, sender, (select(4, ...)))
        else
            EnsureChannel()
        end
    end)

    -- Hide the dedicated mesh channel from the chat display (all traffic is ours).
    if ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, channelString)
            if channelString and channelString:lower():find("chehulmesh", 1, true) then
                return true
            end
            return false
        end)
    end

    -- Hardware-event flush (SendChatMessage to a channel is #hwevent-gated here).
    if WorldFrame and WorldFrame.HookScript then
        WorldFrame:HookScript("OnMouseDown", FlushChannel)
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(6, EnsureChannel)
    end
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
function M:Stats()
    return M.stats
end

function M:HealthLine()
    local s = M.stats
    local line = string.format("addon %d/%d ok", s.ok, s.sent)
    if s.failed > 0 then line = line .. " \194\183 fail " .. s.failed end
    if s.throttled > 0 then line = line .. " \194\183 thr " .. s.throttled end
    if s.chanQueued > 0 then line = line .. " \194\183 realm " .. s.chanSent .. "/" .. s.chanQueued end
    line = line .. " \194\183 recv " .. s.recv
    return line
end

return M
