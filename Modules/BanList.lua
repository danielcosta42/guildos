----------------------------------------------------------------------
-- Guild OS - Ban List
-- Per-guild blacklist (permanent + temp-ban with auto-expiry), synced
-- officer-authoritative (domain "ban"). Alerts officers when a banned
-- player rejoins / whispers / is inspected. IsBanned() gates auto-invite.
----------------------------------------------------------------------
local BanList = {}
BRutus.BanList = BanList

local EXPIRED_GRACE = 7 * 86400    -- keep expired temp-bans 7 days for visibility
local TOMBSTONE_TTL = 30 * 86400   -- keep un-ban tombstones 30 days for sync convergence

function BanList:Initialize()
    BRutus.db.banList = BRutus.db.banList or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("ban", function(env, sender) BanList:OnSync(env, sender) end)
    end
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic, unit-tested via /gos selftest)
----------------------------------------------------------------------
function BanList:_NormalizeKey(name)
    if not name or name == "" then return "" end
    local short = name:match("^([^-]+)") or name
    return short:lower()
end

function BanList:Get(name, store)
    store = store or BRutus.db.banList or {}
    return store[self:_NormalizeKey(name)]
end

function BanList:IsBanned(name, now, store)
    local e = self:Get(name, store)
    if not e or e.removed then return false end
    now = now or GetServerTime()
    if e.expiry and e.expiry <= now then return false end
    return true
end

function BanList:List(store)
    store = store or BRutus.db.banList or {}
    local out = {}
    for _, e in pairs(store) do
        if not e.removed then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

function BanList:Prune(now, store)
    store = store or BRutus.db.banList
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for key, e in pairs(store) do
        local expiredOld = e.expiry and (e.expiry < now - EXPIRED_GRACE)
        local tombOld = e.removed and ((e.ts or 0) < now - TOMBSTONE_TTL)
        if expiredOld or tombOld then
            store[key] = nil
            removed = removed + 1
        end
    end
    return removed
end

----------------------------------------------------------------------
-- Self-tests (pure logic only; use injected stores, never touch real db)
----------------------------------------------------------------------
function BanList:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("banlist.normalize", function()
        local k = BanList:_NormalizeKey("Thrall-Benediction")
        if k ~= "thrall" then return false, "got " .. tostring(k) end
        return true
    end)

    S:Register("banlist.active_permanent", function()
        local store = { thrall = { name = "Thrall", ts = 100 } }
        if not BanList:IsBanned("Thrall", 200, store) then return false, "should be banned" end
        return true
    end)

    S:Register("banlist.temp_active", function()
        local store = { thrall = { name = "Thrall", ts = 100, expiry = 500 } }
        if not BanList:IsBanned("Thrall", 400, store) then return false, "temp should be active" end
        return true
    end)

    S:Register("banlist.temp_expired", function()
        local store = { thrall = { name = "Thrall", ts = 100, expiry = 500 } }
        if BanList:IsBanned("Thrall", 600, store) then return false, "temp should be expired" end
        return true
    end)

    S:Register("banlist.removed_tombstone", function()
        local store = { thrall = { name = "Thrall", ts = 100, removed = true } }
        if BanList:IsBanned("Thrall", 200, store) then return false, "tombstoned = not banned" end
        return true
    end)

    S:Register("banlist.prune_expired", function()
        local store = { old = { name = "Old", ts = 1, expiry = 10 } }
        local n = BanList:Prune(10 + EXPIRED_GRACE + 1, store)
        if n ~= 1 or store.old ~= nil then return false, "expired should prune" end
        return true
    end)
end
