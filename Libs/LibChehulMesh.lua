-- LibChehulMesh v3 - shared mesh for the Chehul addon family (PartyLens, GuildOS,
-- ProfessionHelper). SHIP THIS FILE IDENTICAL in each addon.
--
-- Transport is now AceComm-3.0 + ChatThrottleLib (bundled) — proper priority-based
-- rate limiting (no more disconnect-from-spam) + automatic message chunking (no more
-- manual byte budgets). One instance at _G.ChehulMesh; first addon to load wins.
--
-- BUSES (all automatic, all work from timers — measured on this client):
--   :Guild / :Group / :Proximity(SAY) / :Yell / :Whisper(target)   -> fire-and-forget
--   :Realm(prefix, payload [, key])  -> the WIDE bus. The old click-flushed CHANNEL is
--     DEAD here (timer channel-send is gated; the click-flush delivered 0 in practice),
--     so realm-wide now rides YELL — zone-wide (whole city, >> SAY's ~40yd), timer-safe,
--     exactly how NovaWorldBuffs syncs. Coalesced by key + probabilistic (only a subset
--     yells each cycle, anti-spam) + gated to non-instance/non-ghost. Callers already do
--     Guild/Proximity themselves, so :Realm adds the zone-wide YELL on top. YELL is
--     layer-local (like SAY), so cross-LAYER reach still comes from Guild + Whisper.
--
-- RECEIVE: :Register(prefix, handler) - handler(payload, sender, dist) fires for any
-- distribution (Guild/Group/SAY/YELL/Whisper) of that prefix.

local VERSION = 3
if _G.ChehulMesh and (_G.ChehulMesh.version or 0) >= VERSION then
    return
end

local M = _G.ChehulMesh or {}
_G.ChehulMesh = M

-- Cleanly take over from an older (v1/v2) instance: silence its CHAT_MSG_ADDON receive
-- frame so we don't double-dispatch during a mixed-version transition. Its old
-- WorldFrame click-flush hooks become harmless no-ops (we never fill its channel queue).
if M.frame and M.frame.UnregisterAllEvents then
    pcall(M.frame.UnregisterAllEvents, M.frame)
end

M.version    = VERSION
M.PREFIX_ROOT = "Chehul"
M.CHANNEL    = "ChehulMesh" -- kept for compatibility; the channel is no longer used to send
M.handlers   = M.handlers or {} -- [prefix] = handler(payload, sender, dist); KEPT across an
                                -- upgrade so a still-old sibling's registrations survive (they
                                -- get re-registered with AceComm below).
-- [prefix] = true once an AceComm receive callback is installed. v3-SPECIFIC field name
-- ON PURPOSE: the old v1/v2 used `_registered` for a DIFFERENT meaning (game addon-prefix
-- registration), so reusing it would make Ensure() early-return and leave the mesh
-- receive-DEAD after a v2->v3 upgrade. Do NOT rename this back to `_registered`.
M._commReg = M._commReg or {}
M._realmQueue = M._realmQueue or {} -- [prefix\tkey] = { prefix, payload } pending YELL flush
M.stats = M.stats or {}
do
    local s = M.stats
    s.ok = s.ok or 0; s.fail = s.fail or 0; s.recv = s.recv or 0
    s.yell = s.yell or 0; s.realmQueued = s.realmQueued or 0; s.realmSent = s.realmSent or 0
end

M.YELL_PERCENT   = 34  -- like NWB: only ~1/3 of clients yell each cycle (anti-spam; guild is every cycle)
M.REALM_INTERVAL = 25  -- seconds between YELL-queue flushes

-- ---------------------------------------------------------------------------
-- AceComm transport
-- ---------------------------------------------------------------------------
local AceComm = LibStub and LibStub("AceComm-3.0", true)
local COMM = M._comm or {}
M._comm = COMM

local function OnReceive(prefix, message, dist, sender)
    M.stats.recv = M.stats.recv + 1
    local h = M.handlers[prefix]
    if h then pcall(h, message, sender, dist) end
end

-- Ensure a prefix is registered with AceComm (server delivery + a receive route). Safe
-- to call for send-only prefixes: OnReceive just no-ops when no handler is registered.
local function Ensure(prefix)
    if not AceComm or M._commReg[prefix] then return end
    M._commReg[prefix] = true
    pcall(AceComm.RegisterComm, COMM, prefix, function(_p, message, distribution, sender)
        OnReceive(prefix, message, distribution, sender)
    end)
end

local function Send(prefix, payload, dist, target)
    if not AceComm then M.stats.fail = M.stats.fail + 1; return false end
    Ensure(prefix)
    local ok = pcall(AceComm.SendCommMessage, COMM, prefix, payload, dist, target, "NORMAL")
    if ok then M.stats.ok = M.stats.ok + 1 else M.stats.fail = M.stats.fail + 1 end
    return ok
end
M.SendAddon = Send -- back-compat alias

-- Re-register (with AceComm) any handlers carried over from an upgraded older instance,
-- so receive keeps working even if the addon that registered them isn't reloaded.
for existing in pairs(M.handlers) do
    Ensure(existing)
end

-- ---------------------------------------------------------------------------
-- Receive registration
-- ---------------------------------------------------------------------------
function M:Register(prefix, handler)
    if type(prefix) ~= "string" or prefix == "" or type(handler) ~= "function" then
        return
    end
    M.handlers[prefix] = handler
    Ensure(prefix)
end

-- ---------------------------------------------------------------------------
-- Buses
-- ---------------------------------------------------------------------------
local function CanYell()
    if IsInInstance and IsInInstance() then return false end -- no yell in dungeons/raids/BGs/arenas
    if UnitIsGhost and UnitIsGhost("player") then return false end
    return true
end
M.CanYell = CanYell

function M:Guild(prefix, payload)
    if IsInGuild and not IsInGuild() then return false end
    return Send(prefix, payload, "GUILD")
end

function M:Group(prefix, payload)
    if IsInGroup and not IsInGroup() then return false end
    return Send(prefix, payload, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
end

function M:Proximity(prefix, payload)
    return Send(prefix, payload, "SAY")
end

function M:Yell(prefix, payload)
    if not CanYell() then return false end
    return Send(prefix, payload, "YELL")
end

function M:Whisper(prefix, payload, target)
    if not target or target == "" then return false end
    return Send(prefix, payload, "WHISPER", target)
end

-- Realm-wide (zone-wide via YELL): queue coalesced by key; flushed probabilistically.
function M:Realm(prefix, payload, coalesceKey)
    if type(prefix) ~= "string" or type(payload) ~= "string" then return end
    Ensure(prefix)
    M._realmQueue[prefix .. "\t" .. (coalesceKey or payload)] = { prefix = prefix, payload = payload }
    M.stats.realmQueued = M.stats.realmQueued + 1
end

local function FlushRealm()
    if not next(M._realmQueue) then return end
    -- Only a subset of clients yell each cycle (anti-spam). Presence re-queues every
    -- cycle, so over a couple of cycles everyone's data gets yelled out zone-wide.
    if not (CanYell() and math.random(1, 100) <= M.YELL_PERCENT) then
        return
    end
    local q = M._realmQueue
    M._realmQueue = {}
    for _, item in pairs(q) do
        if Send(item.prefix, item.payload, "YELL") then
            M.stats.yell = M.stats.yell + 1
            M.stats.realmSent = M.stats.realmSent + 1
        end
    end
end
M.FlushRealm = FlushRealm

if not M._realmTicker and C_Timer and C_Timer.NewTicker then
    M._realmTicker = C_Timer.NewTicker(M.REALM_INTERVAL, FlushRealm)
end

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------
function M:Stats()
    return M.stats
end

function M:HealthLine()
    local s = M.stats
    local line = string.format("addon %d ok", s.ok)
    if s.fail > 0 then line = line .. " \194\183 fail " .. s.fail end
    line = line .. " \194\183 yell " .. s.yell .. " \194\183 recv " .. s.recv
    if not AceComm then line = line .. " \194\183 |cffff5555AceComm missing|r" end
    return line
end

return M
