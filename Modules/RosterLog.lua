----------------------------------------------------------------------
-- Guild OS - Roster Log (guild audit trail)
-- Captures join/leave/kick/promote/demote (with actor) from system
-- messages; synced officer-authoritative (domain "audit"); absorbs the
-- old GuildManager action log. Cold-login backfill is a tracked follow-up.
----------------------------------------------------------------------
local RosterLog = {}
BRutus.RosterLog = RosterLog

local CAP = 1000
local MAX_AGE = 90 * 86400

function RosterLog:Initialize()
    BRutus.db.rosterLog = BRutus.db.rosterLog or { events = {} }
    BRutus.db.rosterLog.events = BRutus.db.rosterLog.events or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("audit", function(env) RosterLog:OnSync(env) end)
    end
    self:_MigrateManagementLog()
    self:_SetupDetection()
    self:Prune()
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic; unit-tested via /gos selftest)
----------------------------------------------------------------------
function RosterLog:_NormShort(name)
    if not name or name == "" then return name end
    return name:match("^([^-]+)") or name
end

function RosterLog:_EventId(action, target, author, ts)
    local bucket = math.floor((ts or 0) / 5)
    return string.format("%s|%s|%s|%d", tostring(action), tostring(target or ""),
        tostring(author or ""), bucket)
end

-- Build a Lua pattern from a localized "%s ... %s" format string. Returns
-- the pattern and the number of captures, in order of appearance.
local function fmtToPattern(fmt)
    if not fmt then return nil end
    -- escape magic chars, then turn each %s into a capture
    local esc = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    local pat = esc:gsub("%%s", "(.+)")
    return "^" .. pat .. "$"
end

function RosterLog:_ParseSystem(msg)
    if not msg then return nil end
    msg = strtrim(msg)
    -- join: ERR_GUILD_JOIN_S = "%s has joined the guild."
    local p = fmtToPattern(ERR_GUILD_JOIN_S)
    if p then local t = msg:match(p); if t then return { action = "join", target = self:_NormShort(t) } end end
    -- leave: ERR_GUILD_LEAVE_S = "%s has left the guild."
    p = fmtToPattern(ERR_GUILD_LEAVE_S)
    if p then local t = msg:match(p); if t then return { action = "leave", target = self:_NormShort(t) } end end
    -- kick: ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."  (target, actor)
    p = fmtToPattern(ERR_GUILD_REMOVE_SS)
    if p then local t, a = msg:match(p); if t and a then
        return { action = "kick", target = self:_NormShort(t), author = self:_NormShort(a) } end end
    -- promote: ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."  (actor, target, rank)
    p = fmtToPattern(ERR_GUILD_PROMOTE_SSS)
    if p then local a, t, rk = msg:match(p); if a and t then
        return { action = "promote", target = self:_NormShort(t), author = self:_NormShort(a), detail = rk } end end
    -- demote: ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."  (actor, target, rank)
    p = fmtToPattern(ERR_GUILD_DEMOTE_SSS)
    if p then local a, t, rk = msg:match(p); if a and t then
        return { action = "demote", target = self:_NormShort(t), author = self:_NormShort(a), detail = rk } end end
    return nil
end

function RosterLog:_Insert(evt, store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events)
    if not store or not evt then return false end
    evt.timestamp = evt.timestamp or GetServerTime()
    evt.id = evt.id or self:_EventId(evt.action, evt.target, evt.author, evt.timestamp)
    for i = 1, #store do
        if store[i].id == evt.id then return false end   -- dedup
    end
    store[#store + 1] = evt
    while #store > CAP do table.remove(store, 1) end
    return true
end

function RosterLog:Prune(now, store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events)
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for i = #store, 1, -1 do
        if (store[i].timestamp or 0) < now - MAX_AGE then
            table.remove(store, i); removed = removed + 1
        end
    end
    return removed
end

function RosterLog:GetLog(store)
    store = store or (BRutus.db.rosterLog and BRutus.db.rosterLog.events) or {}
    local out = {}
    for i = #store, 1, -1 do out[#out + 1] = store[i] end
    return out
end

function RosterLog:_MigrateManagementLog()
    if BRutus.db.rosterLog.migrated then return end
    BRutus.db.rosterLog.migrated = true
    local old = BRutus.db.managementLog
    if type(old) == "table" then
        for _, e in ipairs(old) do
            self:_Insert({
                action = e.action, target = e.target, author = e.author,
                detail = e.detail, timestamp = e.timestamp,
            })
        end
    end
end

function RosterLog:Clear()
    if not BRutus:IsOfficer() then return end
    BRutus.db.rosterLog.events = {}
    self:Refresh()
end

function RosterLog:OnSync(env)
    if env.act == "add" and env.data and env.data.evt then
        if self:_Insert(env.data.evt) then self:Refresh() end
    end
end

----------------------------------------------------------------------
-- Recording + detection
----------------------------------------------------------------------
function RosterLog:Add(evt)
    local inserted = self:_Insert(evt)
    if inserted then
        self:_Publish(evt)     -- broadcasts to officers if we are one; no-op for members
        self:Refresh()
    end
    return inserted
end

function RosterLog:Record(action, target, author, detail)
    return self:Add({
        action = action, target = target and self:_NormShort(target) or nil,
        author = author and self:_NormShort(author) or nil, detail = detail,
        timestamp = GetServerTime(),
    })
end

function RosterLog:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

function RosterLog:_SetupDetection()
    self._ready = false
    BRutus.Compat.After(8, function() RosterLog._ready = true end)
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:SetScript("OnEvent", function(_, _, msg)
        if not RosterLog._ready then return end
        local evt = RosterLog:_ParseSystem(msg)
        if evt then RosterLog:Add(evt) end
    end)
end

function RosterLog:_Publish(evt)
    if not BRutus.SyncService or not BRutus:IsOfficer() then return end
    -- broadcast; convergence is by id-dedup on receipt (no rev, no ACK).
    BRutus.SyncService:Publish("audit", "add", { evt = evt })
end

----------------------------------------------------------------------
-- Self-tests
----------------------------------------------------------------------
function RosterLog:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("rosterlog.parse_join", function()
        local e = RosterLog:_ParseSystem("Grefer has joined the guild.")
        if not e or e.action ~= "join" or e.target ~= "Grefer" then return false, "join" end
        return true
    end)
    S:Register("rosterlog.parse_kick", function()
        local e = RosterLog:_ParseSystem("Grefer has been kicked out of the guild by Daniel.")
        if not e or e.action ~= "kick" or e.target ~= "Grefer" or e.author ~= "Daniel" then return false, "kick" end
        return true
    end)
    S:Register("rosterlog.parse_promote", function()
        local e = RosterLog:_ParseSystem("Daniel has promoted Grefer to Officer.")
        if not e or e.action ~= "promote" or e.target ~= "Grefer" or e.author ~= "Daniel" then return false, "promote" end
        return true
    end)
    S:Register("rosterlog.dedup", function()
        local store = {}
        local a = RosterLog:_Insert({ action = "join", target = "X", timestamp = 100 }, store)
        local b = RosterLog:_Insert({ action = "join", target = "X", timestamp = 101 }, store)  -- same 5s bucket
        if not a or b or #store ~= 1 then return false, "dedup" end
        return true
    end)
    S:Register("rosterlog.prune", function()
        local store = { { action = "join", target = "Y", timestamp = 1, id = "y" } }
        local n = RosterLog:Prune(1 + MAX_AGE + 1, store)
        if n ~= 1 or #store ~= 0 then return false, "prune" end
        return true
    end)
end
