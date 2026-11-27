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
--   WhisperQueue:PushAddonGroup(prefix, payloads, target, prio, send)  one message's parts, all or none
--   WhisperQueue:Realm(prefix, payload, key)         an item for the mesh's realm bus; whether it went in
--   WhisperQueue:Release()                           from a click: what waits for one goes now
--   WhisperQueue:QuietMesh(seconds) / :RestoreMesh() the mesh's relay and realm flush off for a while (the error)
--   WhisperQueue.MeshGate(target, parts, prefix)     ChehulMesh.whisperGate (v12): a mesh whisper paid from here
----------------------------------------------------------------------
local CreateFrame = rawget(GuildOS, "CountedCreateFrame") or function(...) return _G.CreateFrame(...) end   -- counted: /gos debug mem
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
Q.MESH_QUIET       = 60    -- seconds the shared mesh is kept quiet after the server's throttle error
Q.MESH_KNOBS       = { "RELAY_BUDGET", "YELL_PER_FLUSH" }   -- the mesh's own pacing fields set to 0 meanwhile
Q.PREPAID_MAX      = 24    -- parts of realm items paid in :Realm that the mesh's gate may still draw on

local RANK = { high = 1, normal = 2, low = 3 }

local S = {
    items    = {},     -- waiting, by rank and then by age
    tokens   = Q.BURST,
    realm    = Q.REALM_BURST,
    at       = nil,    -- when the buckets were last filled
    interval = Q.INTERVAL,
    stepAt   = 0,      -- when the interval last changed
    armed    = false,  -- a timer is set to pump
    stats    = { sent = 0, queued = 0, dropped = 0, throttled = 0, realmIn = 0, realmSkipped = 0,
                 meshIn = 0, meshVeto = 0 },
    prepaid  = 0,      -- parts :Realm paid for the mesh's flush whispers, drawn on by MeshGate
    quietUntil = nil,  -- after the throttle error: no mesh whisper through the gate before this
    meshKept = nil,    -- the mesh's knobs as they were before QuietMesh set them to 0
    sending  = false,  -- inside one of our own items' send: a mesh whisper then is that item, already paid
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

-- The parts of one message (PushAddonGroup) are no use alone: what of `group` still waits goes too.
local function DropGroup(group)
    for j = #S.items, 1, -1 do
        if S.items[j].group == group then
            table.remove(S.items, j)
            S.stats.dropped = S.stats.dropped + 1
        end
    end
end

-- Returns whether a message's other parts went with it (the indexes after `i` may have moved).
local function Drop(i)
    local item = table.remove(S.items, i)
    S.stats.dropped = S.stats.dropped + 1
    if item.group then DropGroup(item.group); return true end
    return false
end

local function Send(item)
    S.sending = true
    local ok, went = pcall(item.send)
    S.sending = false
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
            if Drop(i) then i = 1 end
        elseif fromTimer and NeedsClick(item) then
            i = i + 1
        elseif S.tokens >= 1 then
            table.remove(S.items, i)
            S.tokens = S.tokens - item.cost
            -- A part the game would not send: the message cannot be whole, its other parts would be wasted.
            if not Send(item) and item.group then
                DropGroup(item.group)
                i = 1
            end
        else
            break
        end
    end
    Arm()
end

-- Room for `n` more of `rank` (a message's parts come in together or not at all): the newest of a worse
-- rank make way, a message's parts all together; a "high" is never refused. A message of more parts than
-- QUEUE_MAX needs a queue empty of what it may not push out.
local function Room(rank, n)
    n = math.min(n or 1, Q.QUEUE_MAX)
    local free = Q.QUEUE_MAX - #S.items
    if free >= n then return true end
    if rank ~= RANK.high then
        local worse = 0
        for _, item in ipairs(S.items) do
            if item.rank > rank then worse = worse + 1 end
        end
        if free + worse < n then return false end
    end
    local i = #S.items
    while i >= 1 and Q.QUEUE_MAX - #S.items < n do
        if S.items[i].rank > rank then
            Drop(i)
            i = #S.items
        else
            i = i - 1
        end
    end
    return true
end

-- `items` are one message: all wait, in order, or none does.
local function Enqueue(items)
    if not Active() then
        local all = true
        for _, item in ipairs(items) do
            local ok, went = pcall(item.send)
            if not ok then Fail(went); went = false end
            if went == false then all = false; break end
        end
        return all and "sent" or false
    end
    local rank = RANK[items[1].prio] or RANK.normal
    if not Room(rank, #items) then
        S.stats.dropped = S.stats.dropped + #items
        return false
    end
    local at = #S.items + 1
    while at > 1 and S.items[at - 1].rank > rank do at = at - 1 end
    for k, item in ipairs(items) do
        item.rank = rank
        item.cost = math.max(1, item.cost or 1)
        item.queuedAt = now()
        table.insert(S.items, at + k - 1, item)
    end
    S.stats.queued = S.stats.queued + #items
    Pump(false)
    local held = {}
    for _, item in ipairs(S.items) do held[item] = true end
    local queued = false
    for _, item in ipairs(items) do
        if held[item] then queued = true elseif not item.done then return false end
    end
    return queued and "queued" or "sent"
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
    return Enqueue({ { send = ChatSender(target, text), cost = 1, prio = prio, chat = true, target = target } })
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
    return Enqueue({ { send = send, cost = Q.Parts(payload), prio = prio, prefix = prefix, target = target } })
end

-- One message cut in `payloads` (CommSystem's chunks), each sent by `send(payload)`: the queue takes all of
-- them or none, keeps them in order, and lets none go stale or make way alone, since a message missing a
-- part is lost whole. Returns as :Push.
function Q:PushAddonGroup(prefix, payloads, target, prio, send)
    if type(send) ~= "function" or type(payloads) ~= "table" or #payloads == 0 then return false end
    local group, items = {}, {}
    for i, payload in ipairs(payloads) do
        if type(payload) ~= "string" then return false end
        items[i] = { send = function() return send(payload) end, cost = Q.Parts(payload), prio = prio,
                     prefix = prefix, target = target, group = group }
    end
    return Enqueue(items)
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
    -- Paid now: the mesh's gate lets the flush's whispers for it through without paying twice.
    if mesh.whisperGate == Q.MeshGate then S.prepaid = math.min(Q.PREPAID_MAX, S.prepaid + cost) end
    S.stats.realmIn = S.stats.realmIn + 1
    mesh:Realm(prefix, payload, key)
    return true
end

-- From the player's click: what waits sends now, chat lines included.
function Q:Release()
    if Active() then Pump(false) end
end

-- The server said "too fast": the interval doubles and the bucket empties, and the shared mesh goes quiet too
-- for MESH_QUIET seconds (its whispers count against the same ~30 a minute).
function Q:OnThrottle()
    if not Active() then return end
    local t = now()
    Fill(t)
    S.interval = math.min(Q.MAX_INTERVAL, S.interval * 2)
    S.stepAt = t
    S.tokens = math.min(S.tokens, 0)
    S.realm = math.min(S.realm, 0)
    S.prepaid = 0
    S.stats.throttled = S.stats.throttled + 1
    S.quietUntil = t + Q.MESH_QUIET
    Q:HookMesh()
    Q:QuietMesh(Q.MESH_QUIET)
    Arm()
end

----------------------------------------------------------------------
-- The shared mesh (Libs/LibChehulMesh.lua, not ours to change). Until its own whisper budget (v12) is what every
-- Chehul addon loads, two guards from here, each a no-op where the mesh has not got what it reads:
--   * QuietMesh: after the throttle error its relay budget and its realm flush are set to 0 for MESH_QUIET
--     seconds, then put back as they were (a value somebody else changed meanwhile stands);
--   * MeshGate: where the mesh asks a host before each whisper (ChehulMesh.whisperGate, v12), each one is paid
--     from this queue's bucket, vetoed while our own whispers wait, the bucket is empty or the error is fresh.
--     A realm item :Realm already paid for passes on what it paid; a whisper that is one of our own items (its
--     send goes through the mesh) passes free, being paid already.
----------------------------------------------------------------------
function Q:QuietMesh(seconds)
    local mesh = _G.ChehulMesh
    if type(mesh) ~= "table" then return false end
    seconds = seconds or Q.MESH_QUIET
    local kept, any = S.meshKept or {}, false
    for _, k in ipairs(Q.MESH_KNOBS) do
        if type(mesh[k]) == "number" then
            if kept[k] == nil then kept[k] = mesh[k] end
            mesh[k] = 0
            any = true
        end
    end
    if not any then return false end
    S.meshKept, S.meshOf, S.meshUntil = kept, mesh, now() + seconds
    Compat.After(seconds, function()
        local ok, err = pcall(Q.RestoreMesh, Q)
        if not ok then Fail(err) end
    end)
    return true
end

-- Puts the knobs back once the last quiet spell is over (a later error's own timer does it then).
function Q:RestoreMesh(force)
    local kept, mesh = S.meshKept, S.meshOf
    if not kept then return false end
    if not force and now() < (S.meshUntil or 0) then return false end
    for k, v in pairs(kept) do
        if mesh[k] == 0 then mesh[k] = v end
    end
    S.meshKept, S.meshOf, S.meshUntil = nil, nil, nil
    return true
end

-- ChehulMesh.whisperGate(target, parts, prefix): false vetoes the whisper; anything else lets it go, paid.
function Q.MeshGate(_, parts, _)
    if S.sending or not Active() then return true end
    local t = now()
    Fill(t)
    parts = math.max(1, math.floor(tonumber(parts) or 1))
    if S.prepaid > 0 then
        local use = math.min(S.prepaid, parts)
        S.prepaid, parts = S.prepaid - use, parts - use
        if parts == 0 then
            S.stats.meshIn = S.stats.meshIn + 1
            return true
        end
    end
    if (S.quietUntil and t < S.quietUntil) or Waiting() or S.tokens < 1 then
        S.stats.meshVeto = S.stats.meshVeto + 1
        return false
    end
    S.tokens = S.tokens - parts
    S.stats.meshIn = S.stats.meshIn + 1
    return true
end

-- Registers MeshGate where the mesh asks a host (v12 and later) and no other host holds the gate.
function Q:HookMesh()
    local mesh = _G.ChehulMesh
    if type(mesh) ~= "table" or (tonumber(mesh.version) or 0) < 12 then return false end
    if mesh.whisperGate ~= nil and mesh.whisperGate ~= Q.MeshGate then return false end
    mesh.whisperGate = Q.MeshGate
    return true
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

Q:HookMesh()   -- the mesh in Libs loaded before this file; a newer one another addon loads is hooked at login

if CreateFrame then
    local f = CreateFrame("Frame")
    Compat.RegisterEvent(f, "UI_ERROR_MESSAGE")
    Compat.RegisterEvent(f, "PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LOGIN" then
            pcall(Q.HookMesh, Q)
        elseif Q.IsThrottle(...) then
            local ok, err = pcall(Q.OnThrottle, Q)
            if not ok then Fail(err) end
        end
    end)
end
