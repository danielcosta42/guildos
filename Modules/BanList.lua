----------------------------------------------------------------------
-- Guild OS - Ban List
-- Per-guild blacklist (permanent + temp-ban with auto-expiry), synced
-- officer-authoritative (domain "ban"). Alerts officers when a banned
-- player rejoins / whispers / is inspected. IsBanned() gates auto-invite.
--
-- The alliance (issue #408): an officer may share a local ban with the guild's alliance (a reason
-- from SHARE_REASONS, an optional note), kept on the ban as `entry.share` and sent to the site in the
-- GOSCOMP1 as `banShares`. The site hands back the bans of the alliance's OTHER guilds in the
-- GOSGILD1 (`allianceBans`, read by CompanionImport:AllianceBans), held in memory only. Those only
-- ever ALERT an officer — on a join, a whisper, a tooltip and before a manual invite — and never
-- enter IsBanned(): another guild's ban never blocks the auto-invite; the officer decides.
----------------------------------------------------------------------
local BanList = {}
GuildOS.BanList = BanList
local L = GuildOS.L

local EXPIRED_GRACE = 7 * 86400    -- keep expired temp-bans 7 days for visibility
local TOMBSTONE_TTL = 30 * 86400   -- keep un-ban tombstones 30 days for sync convergence

-- The alliance's contract (issue #408, the site's guildos-web#616): the reasons a shared ban may give,
-- the note's bytes, and how many shares go up and how many of the alliance's bans are read.
BanList.SHARE_REASONS = { "scam", "harassment", "ninja", "cheating", "other" }
BanList.SHARE_NOTE_MAX = 200
BanList.SHARE_EXPORT_MAX = 200
BanList.ALLIANCE_MAX = 200

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
    local held = GuildOS.db.banList[key]
    local entry = {
        -- Banned again: the alliance share stays as it was, shared or withdrawn (#408).
        share   = type(held) == "table" and type(held.share) == "table" and held.share or nil,
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
    local now = GetServerTime()
    local tomb = {
        name = existing.name or key,
        author = GuildOS.Compat.PlayerName(), ts = now, removed = true,
    }
    -- A lifted ban that was shared tells the site so: the share, withdrawn now (#408).
    local share = type(existing.share) == "table" and existing.share or nil
    if share then
        tomb.share = { reason = share.reason, note = share.note, at = share.at, withdrawnAt = share.withdrawnAt or now }
    end
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
    -- An officer on a client before #408 re-bans or lifts with no `share`: the share this client holds stays,
    -- marked withdrawn, so the site hears it was withdrawn instead of the ban staying shared for good.
    local held = GuildOS.db.banList[key]
    if type(entry) == "table" and entry.share == nil and type(held) == "table" and type(held.share) == "table" then
        local carried = {}
        for f, v in pairs(held.share) do carried[f] = v end
        carried.withdrawnAt = carried.withdrawnAt or GetServerTime()
        entry.share = carried
    end
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
-- Sharing a ban with the alliance (issue #408)
----------------------------------------------------------------------
local REASON_SET = {}
for _, r in ipairs(BanList.SHARE_REASONS) do REASON_SET[r] = true end

-- The reason as the contract has it, or nil.
function BanList.ShareReason(v)
    if type(v) == "string" and REASON_SET[v] then return v end
    return nil
end

function BanList.ReasonText(r)
    local t = {
        scam = L["Scam"], harassment = L["Harassment"], ninja = L["Ninja looting"],
        cheating = L["Cheating"], other = L["Other"],
    }
    return t[r] or L["Other"]
end

-- A note for the alliance, or off the network: nothing that opens a colour, a link or a texture, one
-- line, no control character, trimmed, cut to SHARE_NOTE_MAX bytes without splitting a UTF-8
-- character. Nil when nothing is left.
function BanList.CleanNote(v)
    if type(v) ~= "string" then return nil end
    local s = strtrim((v:gsub("|", ""):gsub("%c", " ")))
    local max = BanList.SHARE_NOTE_MAX
    if #s > max then
        local cut = max
        while cut > 0 do
            local b = s:byte(cut + 1)
            if not (b and b >= 0x80 and b <= 0xBF) then break end
            cut = cut - 1
        end
        s = strtrim(s:sub(1, cut))
    end
    return s ~= "" and s or nil
end

-- Whether the ban filed under `key` is shared with the alliance right now.
function BanList:IsShared(key, store)
    store = store or GuildOS.db.banList or {}
    local e = store[key]
    return type(e) == "table" and not e.removed and type(e.share) == "table" and not e.share.withdrawnAt
end

-- Share the standing ban filed under `key` with the alliance. Officers only; the reason is required.
-- True, or false and why: "officer", "missing", "reason".
function BanList:Share(key, reason, note)
    if not GuildOS:IsOfficer() then return false, "officer" end
    local e = key and GuildOS.db.banList[key]
    if type(e) ~= "table" or e.removed then return false, "missing" end
    reason = BanList.ShareReason(reason)
    if not reason then return false, "reason" end
    e.share = { reason = reason, note = BanList.CleanNote(note), at = GetServerTime() }
    self:_Publish(key, e)
    self:Refresh()
    return true
end

-- Stop sharing it: the share stays, withdrawn, so the site hears it ended. False when it was not shared.
function BanList:Unshare(key)
    if not GuildOS:IsOfficer() or not self:IsShared(key) then return false end
    local e = GuildOS.db.banList[key]
    e.share.withdrawnAt = GetServerTime()
    self:_Publish(key, e)
    self:Refresh()
    return true
end

-- The member key for a name an officer typed: the roster's own key when a member matches it ignoring case
-- (so "thrall" goes up as members[].key writes "Thrall"), else the name's key with its first letter capitalised.
function BanList:_MemberKey(who)
    local key = GuildOS:KeyOfRosterName(who)
    if not key then return nil end
    local lower = key:lower()
    for k in pairs(GuildOS.db and GuildOS.db.members or {}) do
        if type(k) == "string" and k:lower() == lower then return k end
    end
    return (key:gsub("^%l", string.upper))
end

-- The companion export's `banShares` (#408): from an officer's client only, every ban this guild ever
-- shared, cleaned again (a share arrives from other officers over sync), newest first, at most
-- SHARE_EXPORT_MAX. `key` is the member key as members[].key builds it; `withdrawnAt` when the officer
-- stopped sharing, the ban was lifted or a temporary one ran out. Nil when there is none.
function BanList:ForExport(store, now)
    if not GuildOS:IsOfficer() then return nil end
    store = store or GuildOS.db.banList or {}
    now = now or GetServerTime()
    local list = {}
    for key, e in pairs(store) do
        local s = type(e) == "table" and type(e.share) == "table" and e.share or nil
        local reason = s and BanList.ShareReason(s.reason)
        local at = s and GuildOS.Finite(s.at)
        local who = type(e) == "table" and type(e.name) == "string" and e.name ~= "" and e.name or key
        local exportKey = reason and at and type(who) == "string" and BanList:_MemberKey(who)
        if exportKey then
            local withdrawn = GuildOS.Finite(s.withdrawnAt)
            if not withdrawn and e.removed then withdrawn = GuildOS.Finite(e.ts) or now end
            local expiry = GuildOS.Finite(e.expiry)
            if not withdrawn and expiry and expiry <= now then withdrawn = expiry end
            list[#list + 1] = {
                key = exportKey, name = who:match("^([^-]+)") or who, reason = reason,
                note = BanList.CleanNote(s.note), at = math.floor(at),
                withdrawnAt = withdrawn and math.floor(withdrawn) or nil,
            }
        end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.key < b.key
    end)
    while #list > BanList.SHARE_EXPORT_MAX do list[#list] = nil end
    return list
end

----------------------------------------------------------------------
-- The alliance's bans (issue #408): in memory, alerts only
----------------------------------------------------------------------
-- The alliance's bans by the key BanList files a name under (_NormalizeKey: the realm on retail, the
-- name alone elsewhere, #184), each key a list. Pure: `list` is CompanionImport:AllianceBans()'s.
function BanList:IndexAllianceBans(list)
    if type(list) ~= "table" then return nil end
    local index = {}
    for _, b in ipairs(list) do
        local k = type(b) == "table" and type(b.key) == "string" and self:_NormalizeKey(b.key) or ""
        if k ~= "" then
            index[k] = index[k] or {}
            local held = index[k]
            held[#held + 1] = b
        end
    end
    return index
end

-- The bans of the alliance this client holds, cleaned, rebuilt only when the inbox's block changes.
function BanList:AllianceBans()
    local I = GuildOS.CompanionImport
    if not (I and I.AllianceBans and I.GuildBlock) then return nil, nil end
    local block = I:GuildBlock()
    if block ~= self._allyBlock or not self._allyHeld then
        self._allyBlock = block
        self._allyList = block and I:AllianceBans() or nil
        self._allyIndex = self:IndexAllianceBans(self._allyList)
        self._allyHeld = true
    end
    return self._allyList, self._allyIndex
end

-- The alliance's bans on `name` (as the game hands it over), for an officer; nil for anybody else or none.
-- `index` is injected by the tests.
function BanList:AllianceBansFor(name, index)
    if type(name) ~= "string" or name == "" or not GuildOS:IsOfficer() then return nil end
    if not index then
        local _
        _, index = self:AllianceBans()
    end
    if not index then return nil end
    local found = index[self:_NormalizeKey(name)]
    if found and #found > 0 then return found end
    return nil
end

-- "Banned in <guild> for <reason>", and "(under appeal)" when it is.
function BanList.AllianceLine(b)
    local fmt = b.appeal and L["Banned in %s for %s (under appeal)"] or L["Banned in %s for %s"]
    return string.format(fmt, b.guild or "?", BanList.ReasonText(b.reason))
end

function BanList:_AllianceAlert(name, bans)
    if not GuildOS:IsOfficer() or type(bans) ~= "table" then return end
    for i = 1, math.min(#bans, 3) do
        local b = bans[i]
        local msg = string.format(L["Alliance ban: %s. %s"], b.name or name, BanList.AllianceLine(b))
        if b.note then msg = msg .. " — " .. b.note end
        GuildOS:Print("|cffFF8800\226\154\160 " .. msg .. "|r")   -- ⚠
        if i == 1 and RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
        end
    end
end

-- Before a manual guild invite: when the alliance has banned `name`, the officer sees why first and
-- `invite` runs only on "Invite anyway". True when held (the caller stops there), false when nothing
-- stands in the way (the caller invites as it always did). Never blocks: an alert, not a ban.
function BanList:HoldInvite(name, invite)
    local bans = self:AllianceBansFor(name)
    if not bans or type(invite) ~= "function" or not GuildOS.ShowDialog then return false end
    local lines = { string.format(L["The alliance has banned %s:"], name) }
    for i = 1, math.min(#bans, 3) do
        lines[#lines + 1] = BanList.AllianceLine(bans[i]) .. (bans[i].note and (" — " .. bans[i].note) or "")
    end
    if #bans > 3 then lines[#lines + 1] = string.format(L["and %d more"], #bans - 3) end
    GuildOS:ShowDialog("GUILDOS_ALLIANCE_BAN_INVITE", table.concat(lines, "\n"), nil, invite)
    return true
end

if GuildOS.Dialogs and not GuildOS.Dialogs["GUILDOS_ALLIANCE_BAN_INVITE"] then
    GuildOS.Dialogs["GUILDOS_ALLIANCE_BAN_INVITE"] = {
        text = "%s",
        button1 = L["Invite anyway"], button2 = L["Cancel"],
        OnAccept = function(dlg, data)
            local invite = data or (dlg and dlg.data)
            if type(invite) == "function" then invite() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
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
            local ally = joiner and BanList:AllianceBansFor(joiner)
            if ally then BanList:_AllianceAlert(joiner, ally) end
        elseif event == "CHAT_MSG_WHISPER" then
            -- The whole sender: on retail the realm tells two namesakes apart (#184).
            local who = arg2 and BanList:_Who(arg2)
            local sender = who and BanList:_NormalizeKey(who)
            if sender and sender ~= "" and not BanList._whisperCd[sender] then
                local banned = BanList:IsBanned(who)
                local ally = BanList:AllianceBansFor(who)
                if banned or ally then
                    BanList._whisperCd[sender] = true
                    GuildOS.Compat.After(60, function() BanList._whisperCd[sender] = nil end)
                end
                if banned then BanList:_Alert(BanList:Get(who)) end
                if ally then BanList:_AllianceAlert(who, ally) end
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
        -- The alliance's, officers only, as an alert (#408).
        local ally = name and BanList:AllianceBansFor(name)
        if ally then
            for i = 1, math.min(#ally, 2) do
                tt:AddLine("\226\154\160 " .. BanList.AllianceLine(ally[i]), 1, 0.53, 0)
            end
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

    -- The alliance's bans match by the key a ban is filed under: with the realm on retail, the name
    -- alone elsewhere (#184), and never enter IsBanned (#408).
    S:Register("banlist.alliance_match", function()
        local index = BanList:IndexAllianceBans({
            { key = "Thrall-Benediction", name = "Thrall", guild = "Horde Co", reason = "scam", at = 1 },
        })
        local hit = BanList:AllianceBansFor("Thrall-Benediction", index)
        local other = BanList:AllianceBansFor("Thrall-Faerlina", index)
        if not GuildOS:IsOfficer() then
            if hit then return false, "a member sees nothing" end
            return true
        end
        if not hit or hit[1].guild ~= "Horde Co" then return false, "the same key should match" end
        if GuildOS.Client.isRetail and other then return false, "a namesake on another realm is somebody else on retail" end
        if not GuildOS.Client.isRetail and not other then return false, "the name alone matches off retail" end
        if BanList:IsBanned("Thrall-Benediction", 10, {}) then return false, "an alliance ban never blocks" end
        return true
    end)

    S:Register("banlist.alliance_line", function()
        local line = BanList.AllianceLine({ guild = "G", reason = "ninja", appeal = true })
        if not line:find("G", 1, true) then return false, "got " .. line end
        if BanList.ShareReason("theft") or not BanList.ShareReason("cheating") then return false, "reason enum" end
        local note = BanList.CleanNote("a|cffff0000b\n" .. string.rep("\195\169", 200))
        if not note or note:find("|", 1, true) or #note > BanList.SHARE_NOTE_MAX then return false, "note not cleaned" end
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
