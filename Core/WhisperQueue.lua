----------------------------------------------------------------------
-- Guild OS - WhisperQueue (issue #393)
-- One queue for every whisper GuildOS sends on WoW: Forever, chat lines and addon messages alike. The
-- server there answers a client that whispers about thirty times a minute with "You are doing that too
-- fast" (ERR_GENERIC_THROTTLE), which reaches the player and every other addon, and refuses what came
-- too fast. So nothing here asks how many whispers a module may send: what goes out leaves at a pace the
-- server takes, the most important first.
--
--   * A bucket of parts. A part is one message on the wire: AceComm splits a payload over 255 bytes into
--     parts of 254, so one 2 KB ad is nine whispers to the server, and it pays nine. BURST parts may leave
--     back to back after a quiet spell; then one every INTERVAL seconds, 15 a minute, half what drew the
--     error. The bucket may go into debt by one big item: it then waits until the debt is paid.
--   * The error itself. UI_ERROR_MESSAGE with ERR_GENERIC_THROTTLE doubles the interval (up to
--     MAX_INTERVAL) and empties the bucket; each RECOVER_SECONDS without another halves it again, back to
--     INTERVAL.
--   * Priority. "high" (an answer someone waits for: a join request, a loot whisper, a reminder) goes
--     first and is never dropped; "normal" (sync) after it, dropped only to make room for a "high"; "low"
--     (gossip, a relayed ad) last, dropped past LOW_TTL or when the queue is full, because the next round
--     sends it again anyway.
--   * The realm bus. Libs/LibChehulMesh.lua is shared by the Chehul family and is not changed here: where
--     YELL is dead (Forever) it sends every realm item by whisper to REALM_FANOUT names. What GuildOS
--     hands it goes through :Realm, which lets an item in only when this bucket and a slower one of its
--     own (REALM_PER_MINUTE parts) can pay for all those whispers; what it refuses, the next relay tick
--     offers again. The mesh's own traffic (its peer exchange, its relay, ChehulNet's hello) stays outside.
--
-- Elsewhere (Anniversary, retail) nothing waits: the queue is off and a whisper goes as it always went.
--
-- API:
--   WhisperQueue:Push(target, text, prio)            a chat whisper; "sent", "queued", or false
--   WhisperQueue:SendNow(target, text)               a chat whisper from the player's own click
--   WhisperQueue:PushAddon(prefix, payload, target, prio, send)  an addon whisper, `send()` doing the sending
--   WhisperQueue:Realm(prefix, payload, key)         an item for the mesh's realm bus; whether it went in
--   WhisperQueue:Release()                           from a click: what waits for one goes now
----------------------------------------------------------------------
local Q = {}
GuildOS.WhisperQueue = Q

local Compat = GuildOS.Compat

Q.INTERVAL         = 4     -- seconds one part costs: 15 a minute at most, half the ~30 that drew the error
Q.MAX_INTERVAL     = 64    -- what the doubling stops at
Q.BURST            = 4     -- parts that may leave back to back after a quiet spell
Q.RECOVER_SECONDS  = 60    -- seconds without the error before the interval halves back
Q.QUEUE_MAX        = 60    -- items waiting at most ("high" ones are never refused)
Q.LOW_TTL          = 90    -- seconds a "low" item may wait before it is stale
Q.REALM_PER_MINUTE = 6     -- parts a minute the realm bus's whispers may take, as the issue measured
Q.REALM_BURST      = 6
Q.ENVELOPE         = 90    -- bytes the mesh's relay envelope adds to a realm item (RL1|id|hops|origin|prefix|)
Q.enabled          = nil   -- nil: on where the game is WoW: Forever; true/false forces it (tests)

local RANK = { high = 1, normal = 2, low = 3 }

local S = {
    items    = {},     -- waiting, by rank and then by age
    tokens   = Q.BURST,
    realm    = Q.REALM_BURST,
    at       = nil,    -- when the buckets were last filled
    interval = Q.INTERVAL,
    stepAt   = 0,      -- when the interval last changed
    armed    = false,  -- a timer is set to pump
    stats    = { sent = 0, queued = 0, dropped = 0, throttled = 0, realmIn = 0, realmSkipped = 0 },
}
Q._state = S

local function now()
    return (GetTime and GetTime()) or 0
end

local function Active()
    if Q.enabled ~= nil then return Q.enabled end
    return GuildOS.Client ~= nil and GuildOS.Client.game == "FOREVER"
end
Q.Active = Active

-- How many messages `payload` takes on the wire.
function Q.Parts(payload)
    local n = type(payload) == "number" and payload or #(payload or "")
    if n <= 255 then return 1 end
    return math.ceil(n / 254)
end

local function Fill(t)
    if not S.at then S.at = t end
    -- Each RECOVER_SECONDS without the error halves the interval again, down to INTERVAL.
    while S.interval > Q.INTERVAL and t - S.stepAt >= Q.RECOVER_SECONDS do
        S.interval = math.max(Q.INTERVAL, S.interval / 2)
        S.stepAt = S.stepAt + Q.RECOVER_SECONDS
    end
    local dt = t - S.at
    if dt > 0 then
        S.tokens = math.min(Q.BURST, S.tokens + dt / S.interval)
        S.realm = math.min(Q.REALM_BURST, S.realm + dt * Q.REALM_PER_MINUTE / 60)
    end
    S.at = t
end

local function Fail(err)
    if GuildOS.RecordError then GuildOS:RecordError("WhisperQueue: " .. tostring(err)) end
end

-- A chat line waits for a click where the game drops one an addon sends from a timer (issue #61).
local function NeedsClick(item)
    return item.chat and Compat.NeedsClick and Compat.NeedsClick()
end

local function Drop(i)
    table.remove(S.items, i)
    S.stats.dropped = S.stats.dropped + 1
end

local function Send(item)
    local ok, went = pcall(item.send)
    if not ok then Fail(went); went = false end
    if went == false then
        S.tokens = S.tokens + item.cost -- nothing reached the server: nothing paid
        S.stats.dropped = S.stats.dropped + 1
        return false
    end
    item.done = true
    S.stats.sent = S.stats.sent + 1
    return true
end

local Pump

-- Whether something waits that a timer can send (a chat line held for a click is not).
local function Waiting()
    for _, item in ipairs(S.items) do
        if not NeedsClick(item) then return true end
    end
    return false
end

local function Arm()
    if S.armed or not Waiting() then return end
    S.armed = true
    -- At most RECOVER_SECONDS: an interval that halves meanwhile shortens the wait too.
    local wait = math.min(Q.RECOVER_SECONDS, math.max(0.25, (1 - S.tokens) * S.interval))
    Compat.After(wait, function()
        S.armed = false
        local ok, err = pcall(Pump, true)
        if not ok then Fail(err) end
    end)
end

-- Sends what the bucket can pay for, in order. From a timer, a chat line where the game wants a click is
-- passed over and keeps its place.
Pump = function(fromTimer)
    local t = now()
    Fill(t)
    local i = 1
    while S.items[i] do
        local item = S.items[i]
        if item.rank == RANK.low and t - item.queuedAt > Q.LOW_TTL then
            Drop(i)
        elseif fromTimer and NeedsClick(item) then
            i = i + 1
        elseif S.tokens >= 1 then
            table.remove(S.items, i)
            S.tokens = S.tokens - item.cost
            Send(item)
        else
            break
        end
    end
    Arm()
end

-- Room for one more of `rank`: the newest of a worse rank makes way; a "high" is never refused.
local function Room(rank)
    if #S.items < Q.QUEUE_MAX then return true end
    for i = #S.items, 1, -1 do
        if S.items[i].rank > rank then Drop(i); return true end
    end
    return rank == RANK.high
end

local function Enqueue(item)
    if not Active() then
        local ok, went = pcall(item.send)
        if not ok then Fail(went); return false end
        return went ~= false and "sent" or false
    end
    item.rank = RANK[item.prio] or RANK.normal
    item.cost = math.max(1, item.cost or 1)
    if not Room(item.rank) then
        S.stats.dropped = S.stats.dropped + 1
        return false
    end
    item.queuedAt = now()
    local at = #S.items + 1
    while at > 1 and S.items[at - 1].rank > item.rank do at = at - 1 end
    table.insert(S.items, at, item)
    S.stats.queued = S.stats.queued + 1
    Pump(false)
    if item.done then return "sent" end
    for _, held in ipairs(S.items) do
        if held == item then return "queued" end
    end
    return false
end

-- A chat line's "No player named" answer is the player's to see; a caller who hides it notes the name first.
local function ChatSender(target, text)
    return function() return Compat.SendWhisper(text, target) end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- A chat whisper of `text` to `target`. `prio` is "high", "normal" (the default) or "low". Returns "sent"
-- (it went now), "queued" (it waits its turn; where the game wants a click for a chat line, the next
-- :Release or whisper from a click sends it) or false (refused: an empty target, a full queue).
function Q:Push(target, text, prio)
    if type(target) ~= "string" or target == "" or type(text) ~= "string" or text == "" then return false end
    return Enqueue({ send = ChatSender(target, text), cost = 1, prio = prio, chat = true, target = target })
end

-- A chat whisper the player's own click sends (a warning, the next recruit): it goes now, because a line held
-- back would need another click to leave, and it is paid for, so what waits behind it waits longer.
function Q:SendNow(target, text)
    if type(target) ~= "string" or target == "" or type(text) ~= "string" then return false end
    local ok = ChatSender(target, text)()
    if Active() then
        Fill(now())
        S.tokens = S.tokens - 1
        if ok then S.stats.sent = S.stats.sent + 1 end
        Pump(false)
    end
    return ok
end

-- An addon whisper of `payload` on `prefix` to `target`: `send()` sends it (through the mesh, AceComm or
-- Compat) and returns false when nothing went. Returns as :Push.
function Q:PushAddon(prefix, payload, target, prio, send)
    if type(send) ~= "function" or type(payload) ~= "string" then return false end
    return Enqueue({ send = send, cost = Q.Parts(payload), prio = prio, prefix = prefix, target = target })
end

-- An item for the mesh's realm bus (ChehulMesh:Realm). Where YELL lives the mesh paces it itself and it
-- goes straight in. Where it is dead the mesh whispers it to REALM_FANOUT names at its next flush, and it
-- goes in only when nothing of ours waits and both buckets can pay for every one of those whispers.
-- Returns whether it went in.
function Q:Realm(prefix, payload, key)
    local mesh = _G.ChehulMesh
    if not (mesh and mesh.Realm) or type(payload) ~= "string" then return false end
    if not (Active() and mesh.dead and mesh.dead.YELL) then
        mesh:Realm(prefix, payload, key)
        return true
    end
    Fill(now())
    if Waiting() or S.tokens < 1 or S.realm < 1 then
        S.stats.realmSkipped = S.stats.realmSkipped + 1
        return false
    end
    local cost = (tonumber(mesh.REALM_FANOUT) or 3) * Q.Parts(#payload + Q.ENVELOPE)
    S.tokens, S.realm = S.tokens - cost, S.realm - cost
    S.stats.realmIn = S.stats.realmIn + 1
    mesh:Realm(prefix, payload, key)
    return true
end

-- From the player's click: what waits sends now, chat lines included.
function Q:Release()
    if Active() then Pump(false) end
end

-- The server said "too fast": the interval doubles and the bucket empties.
function Q:OnThrottle()
    if not Active() then return end
    local t = now()
    Fill(t)
    S.interval = math.min(Q.MAX_INTERVAL, S.interval * 2)
    S.stepAt = t
    S.tokens = math.min(S.tokens, 0)
    S.realm = math.min(S.realm, 0)
    S.stats.throttled = S.stats.throttled + 1
    Arm()
end

function Q:Pending() return #S.items end
function Q:Interval() Fill(now()); return S.interval end

function Q:Stats()
    local out = {}
    for k, v in pairs(S.stats) do out[k] = v end
    out.pending, out.interval = #S.items, S.interval
    return out
end

-- UI_ERROR_MESSAGE is (errorType, message) on today's clients and (message) on older ones.
function Q.IsThrottle(...)
    local text = _G.ERR_GENERIC_THROTTLE
    if not text then return false end
    for i = 1, select("#", ...) do
        if select(i, ...) == text then return true end
    end
    return false
end

if CreateFrame then
    local f = CreateFrame("Frame")
    Compat.RegisterEvent(f, "UI_ERROR_MESSAGE")
    f:SetScript("OnEvent", function(_, _, ...)
        if Q.IsThrottle(...) then
            local ok, err = pcall(Q.OnThrottle, Q)
            if not ok then Fail(err) end
        end
    end)
end
