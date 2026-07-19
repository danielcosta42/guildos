----------------------------------------------------------------------
-- Guild OS - Ban List
-- Per-guild blacklist (permanent + temp-ban with auto-expiry), synced
-- officer-authoritative (domain "ban"). Alerts officers when a banned
-- player rejoins / whispers / is inspected. IsBanned() gates auto-invite.
----------------------------------------------------------------------
local BanList = {}
BRutus.BanList = BanList
local L = BRutus.L

local EXPIRED_GRACE = 7 * 86400    -- keep expired temp-bans 7 days for visibility
local TOMBSTONE_TTL = 30 * 86400   -- keep un-ban tombstones 30 days for sync convergence

function BanList:Initialize()
    BRutus.db.banList = BRutus.db.banList or {}
    if BRutus.SyncService then
        BRutus.SyncService:On("ban", function(env, sender) BanList:OnSync(env, sender) end)
    end
    self:_SetupDetection()
    self:_RegisterTests()
    self:Prune()
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
-- Officer mutations + sync (domain "ban", per-entry revision)
----------------------------------------------------------------------
function BanList:Add(name, reason, durationSec)
    if not BRutus:IsOfficer() then
        BRutus:Print(L["|cffFF4444Officers only.|r"])
        return false
    end
    local key = self:_NormalizeKey(name)
    if key == "" then return false end
    local now = GetServerTime()
    local entry = {
        name    = name:match("^([^-]+)") or name,
        reason  = strtrim(reason or "") ~= "" and strtrim(reason) or L["(no reason)"],
        author  = UnitName("player"),
        ts      = now,
        expiry  = durationSec and (now + durationSec) or nil,
    }
    BRutus.db.banList[key] = entry
    self:_Publish(key, entry)
    self:Refresh()
    return true
end

function BanList:Remove(name)
    if not BRutus:IsOfficer() then return false end
    local key = self:_NormalizeKey(name)
    local existing = BRutus.db.banList[key]
    local tomb = {
        name = (existing and existing.name) or (name:match("^([^-]+)") or name),
        author = UnitName("player"), ts = GetServerTime(), removed = true,
    }
    BRutus.db.banList[key] = tomb
    self:_Publish(key, tomb)
    self:Refresh()
    return true
end

function BanList:_Publish(key, entry)
    if not BRutus.SyncService then return end
    local rev = BRutus.SyncService:NextRevision("ban", key)
    -- broadcast to all officers; ACK is point-to-point so not used here —
    -- convergence is via revision-check + the periodic 5-min sync.
    BRutus.SyncService:Publish("ban", "set", { key = key, entry = entry }, { rev = rev })
end

function BanList:_ApplyRemote(key, entry, rev)
    if not BRutus.SyncService:ShouldApply("ban", key, rev) then return false end
    BRutus.db.banList[key] = entry
    BRutus.SyncService:SetRevision("ban", key, rev)
    return true
end

function BanList:OnSync(env)
    if env.act ~= "set" or not env.data or not env.data.key then return end
    if self:_ApplyRemote(env.data.key, env.data.entry, env.rev) then
        self:Refresh()
    end
end

function BanList:Refresh()
    if self.uiRefresh then BRutus:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Detection & alerts (officer-facing)
----------------------------------------------------------------------
function BanList:_Alert(entry)
    if not BRutus:IsOfficer() then return end
    local when = date("%Y-%m-%d", entry.ts or 0)
    local msg = string.format(L["Banned %s (%s) — banned by %s on %s"],
        entry.name or "?", entry.reason or "?", entry.author or "?", when)
    BRutus:Print("|cffFF4444\226\155\148 " .. msg .. "|r")   -- ⛔
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
end

-- Parse "%s has joined the guild." locale-safely (mirrors RecruitmentSystem's
-- join detection). Lighter than diffing the whole roster on GUILD_ROSTER_UPDATE,
-- which the project quality checklist warns against on rapid-fire events.
function BanList:_ParseJoin(sysMsg)
    if not sysMsg then return nil end
    local name
    if ERR_GUILD_JOIN_S then
        name = sysMsg:match((ERR_GUILD_JOIN_S:gsub("%%s", "(.+)")))
    end
    if not name then
        name = sysMsg:match("(.+) entrou na guilda%.")
            or sysMsg:match("(.+) has joined the guild%.")
    end
    if not name then return nil end
    return name:match("^([^-]+)") or name
end

function BanList:_SetupDetection()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_SYSTEM")
    f:RegisterEvent("CHAT_MSG_WHISPER")
    -- give the db time to load before trusting cold-login join spam
    self._ready = false
    self._whisperCd = {}
    BRutus.Compat.After(8, function() BanList._ready = true end)
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "CHAT_MSG_SYSTEM" then
            if not BanList._ready then return end
            local joiner = BanList:_ParseJoin(arg1)
            if joiner and BanList:IsBanned(joiner) then
                BanList:_Alert(BanList:Get(joiner))
            end
        elseif event == "CHAT_MSG_WHISPER" then
            local sender = arg2 and (arg2:match("^([^-]+)") or arg2)
            if sender and BanList:IsBanned(sender) and not BanList._whisperCd[sender] then
                BanList._whisperCd[sender] = true
                BRutus.Compat.After(60, function() BanList._whisperCd[sender] = nil end)
                BanList:_Alert(BanList:Get(sender))
            end
        end
    end)

    -- Tooltip flag on banned units
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt)
            local _, unit = tt:GetUnit()
            local name = unit and UnitName(unit)
            if name and BanList:IsBanned(name) then
                local e = BanList:Get(name)
                tt:AddLine("\226\155\148 " .. L["BANNED"] .. " — " ..
                    (e.reason or "?") .. " (" .. (e.author or "?") .. ")", 1, 0.2, 0.2)
                tt:Show()
            end
        end)
    end
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

    S:Register("banlist.parse_join", function()
        local n = BanList:_ParseJoin("Grefer has joined the guild.")
        if n ~= "Grefer" then return false, "got " .. tostring(n) end
        return true
    end)
end
