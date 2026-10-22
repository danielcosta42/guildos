----------------------------------------------------------------------
-- Guild OS - Ban List
-- Per-guild blacklist (permanent + temp-ban with auto-expiry), synced
-- officer-authoritative (domain "ban"). Alerts officers when a banned
-- player rejoins / whispers / is inspected. IsBanned() gates auto-invite.
----------------------------------------------------------------------
local BanList = {}
GuildOS.BanList = BanList
local L = GuildOS.L

local EXPIRED_GRACE = 7 * 86400    -- keep expired temp-bans 7 days for visibility
local TOMBSTONE_TTL = 30 * 86400   -- keep un-ban tombstones 30 days for sync convergence

function BanList:Initialize()
    GuildOS.db.banList = GuildOS.db.banList or {}
    if GuildOS.SyncService then
        GuildOS.SyncService:On("ban", function(env, sender) BanList:OnSync(env, sender) end)
    end
    self:_SetupDetection()
    self:_RegisterTests()
    self:Prune()
end

----------------------------------------------------------------------
-- Pure helpers (deterministic, unit-tested via /gos selftest)
----------------------------------------------------------------------
-- The key a ban is filed under: the name alone, lower case, on WoW: Forever (no realms) and TBC
-- Anniversary (as it always was). On retail a guild spans connected realms and two players there
-- can share a name, so the key keeps the realm, normalized, lower case; a name without one is on
-- this client's realm (issue #184).
function BanList:_NormalizeKey(name)
    if not name or name == "" then return "" end
    if GuildOS.Client.isRetail then return (GuildOS:KeyOfRosterName(name) or ""):lower() end
    local short = name:match("^([^-]+)") or name
    return short:lower()
end

-- A ban in force at `now`: neither lifted nor a temporary one run out.
local function inForce(e, now)
    return e ~= nil and not e.removed and not (e.expiry and e.expiry <= now)
end

-- The ban a name points at, and the key it is filed under. On retail a ban in force under the
-- whole key, else one filed under the name alone before issue #184, which holds for that name on
-- every realm (lifting the whole key's ban, or its running out, does not lift it), else the whole
-- key's entry, lifted, run out or absent. A name without a realm is this realm's: never a guess at
-- a namesake elsewhere.
function BanList:_Find(name, store, now)
    store = store or GuildOS.db.banList or {}
    now = now or GetServerTime()
    local key = self:_NormalizeKey(name)
    local held = store[key]
    if key == "" or not GuildOS.Client.isRetail or inForce(held, now) then return key, held end
    local short = (name:match("^([^-]+)") or name):lower()
    local old = store[short]
    if inForce(old, now) then return short, old end
    return key, held
end

-- The key `Remove` lifts for a name an officer typed: elsewhere the name alone. On retail a
-- name with a realm is that whole key; one without is the standing ban filed under the name
-- alone before issue #184 when it is still in force, else this realm's (issue #184).
function BanList:_RemovalKey(name, store, now)
    store = store or GuildOS.db.banList or {}
    local key = self:_NormalizeKey(name)
    if not GuildOS.Client.isRetail or key == "" or name:find("-", 1, true) then return key end
    local old = store[name:lower()]
    if inForce(old, now or GetServerTime()) then return name:lower() end
    return key
end

function BanList:Get(name, store, now)
    if not name or name == "" then return nil end
    local _, entry = self:_Find(name, store, now)
    return entry
end

-- How a ban names somebody, and how a name the game hands over is looked up: with the realm on
-- retail, where a name that comes without one is on this client's realm; the name alone elsewhere.
function BanList:_Who(name)
    if GuildOS.Client.isRetail then return GuildOS:KeyOfRosterName(name) end
    return name:match("^([^-]+)") or name
end

function BanList:IsBanned(name, now, store)
    now = now or GetServerTime()
    return inForce(self:Get(name, store, now), now)
end

-- The standing bans, newest first, each a copy carrying the `key` it is filed under: the list
-- removes a row by that key (RemoveKey), never by its name (issue #184).
function BanList:List(store)
    store = store or GuildOS.db.banList or {}
    local out = {}
    for key, e in pairs(store) do
        if not e.removed then
            local row = { key = key }
            for f, v in pairs(e) do row[f] = v end
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

function BanList:Prune(now, store)
    store = store or GuildOS.db.banList
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
    if not GuildOS:IsOfficer() then
        GuildOS:Print(L["|cffFF4444Officers only.|r"])
        return false
    end
    local key = self:_NormalizeKey(name)
    if key == "" then return false end
    local now = GetServerTime()
    local entry = {
        name    = self:_Who(name),
        reason  = strtrim(reason or "") ~= "" and strtrim(reason) or L["(no reason)"],
        author  = GuildOS.Compat.PlayerName(),
        ts      = now,
        expiry  = durationSec and (now + durationSec) or nil,
    }
    GuildOS.db.banList[key] = entry
    self:_Publish(key, entry)
    self:Refresh()
    return true
end

-- Lift a ban by the name an officer typed (/gos unban; `_RemovalKey`). False when none stands there.
function BanList:Remove(name)
    if not name or name == "" then return false end
    return self:RemoveKey(self:_RemovalKey(name))
end

-- Lift the ban filed under `key`, exactly that one: the ban list's own rows (issue #184). False,
-- and nothing written, when no ban stands there (none, or already lifted): `/gos unban` says so.
function BanList:RemoveKey(key)
    if not GuildOS:IsOfficer() or not key or key == "" then return false end
    local existing = GuildOS.db.banList[key]
    if not existing or existing.removed then return false end
    local tomb = {
        name = existing.name or key,
        author = GuildOS.Compat.PlayerName(), ts = GetServerTime(), removed = true,
    }
    GuildOS.db.banList[key] = tomb
    self:_Publish(key, tomb)
    self:Refresh()
    return true
end

function BanList:_Publish(key, entry)
    if not GuildOS.SyncService then return end
    local rev = GuildOS.SyncService:NextRevision("ban", key)
    -- Broadcast to the whole guild (Publish has no target); SyncService:Validate
    -- restricts who may *apply* a ban write to officers, not who receives it.
    -- ACK is point-to-point, so it's not used for a broadcast: online clients
    -- converge at broadcast time via the revision-check (highest rev wins).
    -- Cold-sync: an officer offline at ban time converges on login via
    -- BanList:Backfill(), which re-emits every entry at its STORED revision
    -- from CommSystem:HandleRequest (idempotent by the same revision check).
    GuildOS.SyncService:Publish("ban", "set", { key = key, entry = entry }, { rev = rev })
end

----------------------------------------------------------------------
-- Cold-sync backfill: re-broadcast every current ban entry (including
-- un-ban tombstones, so removals also propagate) at its STORED revision,
-- never a fresh one. An officer offline when a ban/un-ban happened misses
-- the mutation broadcast; answering the login/periodic sync REQUEST with
-- this lets them converge without waiting for the next mutation.
-- Idempotent: preserving the stored revision means ShouldApply drops the
-- re-broadcast for a peer already at that revision and applies it only for
-- one that missed the change, so a stale re-emit can never roll back a newer
-- edit. Officers only; members must never re-broadcast authoritative bans.
----------------------------------------------------------------------
function BanList:Backfill()
    if not GuildOS:IsOfficer() or not GuildOS.SyncService then return end
    for key, entry in pairs(GuildOS.db.banList or {}) do
        local rev = GuildOS.SyncService:GetRevision("ban", key)
        GuildOS.SyncService:Publish("ban", "set", { key = key, entry = entry }, { rev = rev })
    end
end

function BanList:_ApplyRemote(key, entry, rev)
    if not GuildOS.SyncService:ShouldApply("ban", key, rev) then return false end
    GuildOS.db.banList[key] = entry
    GuildOS.SyncService:SetRevision("ban", key, rev)
    return true
end

function BanList:OnSync(env)
    if env.act ~= "set" or not env.data or not env.data.key then return end
    if self:_ApplyRemote(env.data.key, env.data.entry, env.rev) then
        self:Refresh()
    end
end

function BanList:Refresh()
    if self.uiRefresh then GuildOS:SafeCall(self.uiRefresh) end
end

----------------------------------------------------------------------
-- Detection & alerts (officer-facing)
----------------------------------------------------------------------
function BanList:_Alert(entry)
    if not GuildOS:IsOfficer() then return end
    local when = date("%Y-%m-%d", entry.ts or 0)
    local msg = string.format(L["Banned %s (%s) — banned by %s on %s"],
        entry.name or "?", entry.reason or "?", entry.author or "?", when)
    GuildOS:Print("|cffFF4444\226\155\148 " .. msg .. "|r")   -- ⛔
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
    local args = GuildOS:MatchFormat(sysMsg, ERR_GUILD_JOIN_S)   -- "%s" or a numbered "%1$s" (#160)
    if args then name = args[1] end
    if not name then
        name = sysMsg:match("(.+) entrou na guilda%.")
            or sysMsg:match("(.+) has joined the guild%.")
    end
    if not name then return nil end
    return self:_Who(name)   -- with the realm on retail, where it tells namesakes apart (#184)
end

function BanList:_SetupDetection()
    local f = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_SYSTEM")
    GuildOS.Compat.RegisterEvent(f, "CHAT_MSG_WHISPER")
    -- give the db time to load before trusting cold-login join spam
    self._ready = false
    self._whisperCd = {}
    GuildOS.Compat.After(8, function() BanList._ready = true end)
    f:SetScript("OnEvent", function(_, event, arg1, arg2)
        if GuildOS.Compat.IsSecret(arg1, arg2) then return end  -- chat in lockdown: nothing readable
        if not GuildOS:IsOfficer() then return end
        if event == "CHAT_MSG_SYSTEM" then
            if not BanList._ready then return end
            local joiner = BanList:_ParseJoin(arg1)
            if joiner and BanList:IsBanned(joiner) then
                BanList:_Alert(BanList:Get(joiner))
            end
        elseif event == "CHAT_MSG_WHISPER" then
            -- The whole sender: on retail the realm tells two namesakes apart (#184).
            local who = arg2 and BanList:_Who(arg2)
            local sender = who and BanList:_NormalizeKey(who)
            if sender and sender ~= "" and BanList:IsBanned(who) and not BanList._whisperCd[sender] then
                BanList._whisperCd[sender] = true
                GuildOS.Compat.After(60, function() BanList._whisperCd[sender] = nil end)
                BanList:_Alert(BanList:Get(who))
            end
        end
    end)

    -- Tooltip flag on banned units
    GuildOS.Compat.HookTooltip(GameTooltip, "OnTooltipSetUnit", function(tt)
        local _, unit = GuildOS.Compat.TooltipUnit(tt)
        -- Not UnitName: on a client that keeps a unit's identity secret the name
        -- comes back as a value the match inside IsBanned raises on
        -- (docs/forever/README.md), and the unit token itself can be secret,
        -- which UnitClass refuses outright (#116). UnitIdentity answers nothing
        -- for either. Reachable only since the hook started landing on that client.
        local name, realm
        if unit then name, realm = GuildOS.Compat.UnitIdentity(unit) end
        name = name and GuildOS:GetPlayerKey(name, realm)   -- with its realm on retail (#184)
        if name and BanList:IsBanned(name) then
            local e = BanList:Get(name)
            tt:AddLine("\226\155\148 " .. L["BANNED"] .. " — " ..
                (e.reason or "?") .. " (" .. (e.author or "?") .. ")", 1, 0.2, 0.2)
            tt:Show()
        end
    end)
end

----------------------------------------------------------------------
-- Self-tests (pure logic only; use injected stores, never touch real db)
----------------------------------------------------------------------
function BanList:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest

    S:Register("banlist.normalize", function()
        local k = BanList:_NormalizeKey("Thrall-Benediction")
        local want = GuildOS.Client.isRetail and "thrall-benediction" or "thrall"   -- the realm stays on retail (#184)
        if k ~= want then return false, "got " .. tostring(k) end
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
        if n ~= BanList:_Who("Grefer") then return false, "got " .. tostring(n) end   -- realm and all on retail (#184)
        return true
    end)

    S:Register("banlist.list_hides_removed", function()
        local store = { a = { name = "A", ts = 2 }, b = { name = "B", ts = 1, removed = true } }
        local out = BanList:List(store)
        if #out ~= 1 or out[1].name ~= "A" then
            return false, "tombstone should be hidden, active kept"
        end
        return true
    end)
end
