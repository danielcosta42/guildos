----------------------------------------------------------------------
-- Guild OS - LFG Board
-- Members mark themselves available for a group (role + note + TTL).
-- Everyone sees a live board. An entry is always keyed by the comm
-- envelope sender, so nobody can publish availability for someone else.
----------------------------------------------------------------------
local LFGBoard = {}
BRutus.LFGBoard = LFGBoard
local L = BRutus.L
local LibSerialize = LibStub("LibSerialize")

local DEFAULT_TTL = 5400   -- 90 minutes
local NOTE_MAX    = 60

LFGBoard.DEFAULTS = { notify = false, lastRole = "ANY", lastNote = "", lastTtl = DEFAULT_TTL }
LFGBoard.ROLES    = { "ANY", "TANK", "HEALER", "DPS" }

function LFGBoard:Initialize()
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    BRutus.db.lfgPrefs = BRutus.db.lfgPrefs or {}
    for k, v in pairs(self.DEFAULTS) do
        if BRutus.db.lfgPrefs[k] == nil then BRutus.db.lfgPrefs[k] = v end
    end
    self:Prune()
    self:_RegisterTests()
end

----------------------------------------------------------------------
-- Pure helpers (unit tested)
----------------------------------------------------------------------
function LFGBoard:_IsActive(entry, now)
    if not entry or not entry.ts then return false end
    return (entry.ts + (entry.ttl or DEFAULT_TTL)) > (now or 0)
end

function LFGBoard:_Remaining(entry, now)
    if not self:_IsActive(entry, now) then return 0 end
    return math.floor(((entry.ts + (entry.ttl or DEFAULT_TTL)) - (now or 0)) / 60)
end

-- onlineSet (optional): { [key] = true } of members currently online.
function LFGBoard:ActiveList(store, now, onlineSet)
    local out = {}
    for key, e in pairs(store or {}) do
        if self:_IsActive(e, now) and (not onlineSet or onlineSet[key]) then
            out[#out + 1] = {
                key = key, name = key:match("^([^-]+)") or key,
                role = e.role or "ANY", note = e.note or "", ts = e.ts, ttl = e.ttl,
            }
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

function LFGBoard:Prune(now, store)
    store = store or BRutus.db.lfgBoard
    if not store then return 0 end
    now = now or GetServerTime()
    local removed = 0
    for k, e in pairs(store) do
        if not self:_IsActive(e, now) then store[k] = nil; removed = removed + 1 end
    end
    return removed
end

-- Whitelist an incoming role against the known set. Anything that is not a
-- string, or not one of LFGBoard.ROLES (a forged length, a color/texture
-- escape sequence, a number/boolean/table that survived LibSerialize), falls
-- back to "ANY". Shared by HandleEntry and the self test so the rule cannot
-- drift between production and the test that pins it.
function LFGBoard:_SanitizeRole(role)
    return (type(role) == "string" and tContains(self.ROLES, role) and role) or "ANY"
end

----------------------------------------------------------------------
-- Self declare (publishes only your OWN entry)
----------------------------------------------------------------------
local function myKey()
    return BRutus:GetPlayerKey(UnitName("player"), GetRealmName())
end

function LFGBoard:SetAvailable(role, note, ttl)
    note = (note or ""):sub(1, NOTE_MAX)
    ttl = ttl or BRutus.db.lfgPrefs.lastTtl or DEFAULT_TTL
    role = role or BRutus.db.lfgPrefs.lastRole or "ANY"
    local entry = { role = role, note = note, ts = GetServerTime(), ttl = ttl }
    BRutus.db.lfgBoard[myKey()] = entry
    BRutus.db.lfgPrefs.lastRole, BRutus.db.lfgPrefs.lastNote, BRutus.db.lfgPrefs.lastTtl = role, note, ttl
    if BRutus.CommSystem then
        BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ role = role, note = note, ttl = ttl }))
    end
    self:Refresh()
end

function LFGBoard:ClearAvailable()
    BRutus.db.lfgBoard[myKey()] = nil
    if BRutus.CommSystem then
        BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.LFG,
            LibSerialize:Serialize({ clear = true }))
    end
    self:Refresh()
end

function LFGBoard:AmAvailable()
    return self:_IsActive(BRutus.db.lfgBoard[myKey()], GetServerTime())
end

-- Incoming: the key ALWAYS comes from the envelope sender, never the payload.
function LFGBoard:HandleEntry(sender, data)
    if not sender then return end
    local ok, p = LibSerialize:Deserialize(data)
    if not ok or type(p) ~= "table" then return end
    local short = sender:match("^([^-]+)") or sender
    local realm = sender:match("-(.+)$") or GetRealmName()
    local key = BRutus:GetPlayerKey(short, realm)
    BRutus.db.lfgBoard = BRutus.db.lfgBoard or {}
    if p.clear then
        BRutus.db.lfgBoard[key] = nil
    else
        local wasActive = self:_IsActive(BRutus.db.lfgBoard[key], GetServerTime())
        BRutus.db.lfgBoard[key] = {
            role = self:_SanitizeRole(p.role),
            note = tostring(p.note or ""):sub(1, NOTE_MAX),
            ts = GetServerTime(),
            ttl = tonumber(p.ttl) or DEFAULT_TTL,
        }
        if not wasActive and BRutus.db.lfgPrefs.notify and key ~= myKey() then
            BRutus:Print(string.format(L["%s is available: %s"], short,
                (p.note ~= "" and p.note) or L["(no note)"]))
        end
    end
    self:Refresh()
end

function LFGBoard:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Self tests
----------------------------------------------------------------------
function LFGBoard:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    S:Register("lfg.active", function()
        if not LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 130) then return false, "should be active" end
        if LFGBoard:_IsActive({ ts = 100, ttl = 60 }, 200) then return false, "should be expired" end
        return true
    end)
    S:Register("lfg.remaining", function()
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 300) ~= 5 then return false, "5 min left" end
        if LFGBoard:_Remaining({ ts = 0, ttl = 600 }, 999) ~= 0 then return false, "expired => 0" end
        return true
    end)
    S:Register("lfg.activelist_sorted_and_filtered", function()
        local store = {
            ["A-R"] = { ts = 100, ttl = 600, note = "a" },
            ["B-R"] = { ts = 200, ttl = 600, note = "b" },
            ["C-R"] = { ts = 1,   ttl = 5,   note = "expired" },
        }
        local out = LFGBoard:ActiveList(store, 300)
        if #out ~= 2 or out[1].key ~= "B-R" then return false, "newest first, expired dropped" end
        local only = LFGBoard:ActiveList(store, 300, { ["A-R"] = true })
        if #only ~= 1 or only[1].key ~= "A-R" then return false, "online filter" end
        return true
    end)
    S:Register("lfg.prune", function()
        local store = { ["X-R"] = { ts = 1, ttl = 5 }, ["Y-R"] = { ts = 100, ttl = 600 } }
        local n = LFGBoard:Prune(300, store)
        if n ~= 1 or store["X-R"] ~= nil or store["Y-R"] == nil then return false, "prune" end
        return true
    end)
    S:Register("lfg.role_whitelist", function()
        if LFGBoard:_SanitizeRole("TANK") ~= "TANK" then return false, "valid role kept" end
        if LFGBoard:_SanitizeRole("|cffff0000EVIL|r") ~= "ANY" then return false, "escape string rejected" end
        if LFGBoard:_SanitizeRole(42) ~= "ANY" then return false, "non string rejected" end
        if LFGBoard:_SanitizeRole(nil) ~= "ANY" then return false, "nil defaults" end
        return true
    end)
end
