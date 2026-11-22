----------------------------------------------------------------------
-- Guild OS - Alt Auto-Detect
-- Detects the player's own same-account characters via the account-wide
-- SavedVariables (GuildOSDB is shared across all chars on the game account)
-- and offers a one-click link. Own alts only; others' alts are never
-- auto-detectable (no API reveals another player's account).
----------------------------------------------------------------------
local AltAutoDetect = {}
GuildOS.AltAutoDetect = AltAutoDetect

local L = GuildOS.L
local LibSerialize = LibStub("GuildOS-LibSerialize")

-- Stable signature for a detected group, used to dedupe the "declined"
-- marker: same set of keys => same signature regardless of order.
local function GroupSignature(group)
    local sorted = {}
    for i, key in ipairs(group) do sorted[i] = key end
    table.sort(sorted)
    return table.concat(sorted, "|")
end

function AltAutoDetect:Initialize()
    self:RecordSelf()
    self:_RegisterTests()
    -- login prompt is scheduled by Task 3 (after the roster is available)
    if self._SchedulePrompt then self:_SchedulePrompt() end
end

-- Account-wide registry lives at the GuildOSDB root (shared across every
-- character on the account), NOT under the per-guild db that /gos reset wipes.
function AltAutoDetect:RecordSelf()
    if not GuildOSDB then return end
    GuildOSDB.accountChars = GuildOSDB.accountChars or {}
    local name = GuildOS.Compat.PlayerName()
    if not name then return end
    -- The realm GuildOS:RealmName() reads back when the client answers none (issue #394).
    local realm = GuildOS:RealmName()
    local key = GuildOS:GetPlayerKey(name, realm)
    local _, classFile = UnitClass("player")
    GuildOSDB.accountChars[key] = {
        name = name, realm = realm, class = classFile,
        level = UnitLevel("player"), guild = GetGuildInfo("player"),
        ts = GetServerTime(),
    }
end

function AltAutoDetect:_GuildSet()
    local set = {}
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local short = full:match("^([^-]+)") or full
            local realm = full:match("-(.+)$") or GetRealmName()
            set[GuildOS:GetPlayerKey(short, realm)] = true
        end
    end
    return set
end

-- Pure: the links that make `main` the one main of `group`: every other member points at it,
-- it points at nobody, and a character still pointing at a member that stops being a main
-- follows to the new one (no alt of an alt). Returns a new table and how many entries changed.
function AltAutoDetect:PlanGroup(altLinks, group, main)
    local out = {}
    for k, v in pairs(altLinks or {}) do out[k] = v end
    local inGroup = {}
    for _, k in ipairs(group or {}) do inGroup[k] = true end
    for k, v in pairs(out) do
        if inGroup[v] and v ~= main and not inGroup[k] then out[k] = main end
    end
    for k in pairs(inGroup) do
        if k == main then out[k] = nil else out[k] = main end
    end
    local changed = 0
    local seen = {}
    for k, v in pairs(out) do
        seen[k] = true
        if (altLinks or {})[k] ~= v then changed = changed + 1 end
    end
    for k in pairs(altLinks or {}) do
        if not seen[k] then changed = changed + 1 end
    end
    return out, changed
end

-- Pure: from the account chars that are ALSO current guild members, if 2+
-- exist and they do not already share one main (whichever of them it is),
-- return the group and the suggested main. Else nil. The suggestion keeps the
-- main the group already has; with none it is the highest level, and a tie
-- goes to the name, so the same group always gets the same answer (#353).
function AltAutoDetect:DetectOwnAlts(accountChars, guildSet, altLinks)
    altLinks = altLinks or {}
    local group = {}
    for key, info in pairs(accountChars or {}) do
        local lk = GuildOS:LocalMemberKey(key)   -- recorded on another realm's client (#97)
        if guildSet[lk] then group[#group + 1] = { key = lk, level = info.level or 0 } end
    end
    if #group < 2 then return nil end
    table.sort(group, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.key < b.key
    end)
    local roots, nRoots = {}, 0
    for _, g in ipairs(group) do
        local root = altLinks[g.key] or g.key
        if not roots[root] then roots[root] = 0; nRoots = nRoots + 1 end
        roots[root] = roots[root] + 1
    end
    if nRoots == 1 then return nil end            -- already one person, whoever is the main
    local main
    for _, g in ipairs(group) do                 -- the main the group already has, if any
        local c = roots[g.key]
        if c and c >= 2 and altLinks[g.key] == nil and (not main or c > roots[main]) then main = g.key end
    end
    main = main or group[1].key
    local keys = {}
    for _, g in ipairs(group) do keys[#keys + 1] = g.key end
    return { group = keys, main = main }
end

-- Returns how many links changed. An officer writes and publishes them; a member applies
-- them to their own view, asks the officers and keeps the claim until an officer's list
-- carries it, since a claim nobody heard would be wiped by the next list (#353).
function AltAutoDetect:LinkOwnAlts(mainKey, altKeys)
    if not mainKey or not altKeys then return 0 end
    local links, changed = self:PlanGroup(GuildOS.db.altLinks, altKeys, mainKey)
    if GuildOS:IsOfficer() then
        if changed > 0 then
            GuildOS.db.altLinks = links
            if GuildOS.CommSystem then GuildOS.CommSystem:BroadcastAltLinks() end
        end
        return changed
    end
    GuildOS.db.altLinks = links
    local alts = {}
    for _, k in ipairs(altKeys) do
        if k ~= mainKey then alts[#alts + 1] = k end
    end
    self:_KeepPending(mainKey, alts)
    self:_SendClaim(mainKey, alts)
    return changed
end

function AltAutoDetect:_SendClaim(mainKey, alts)
    if not GuildOS.CommSystem then return end
    local payload = LibSerialize:Serialize({ main = mainKey, alts = alts })
    GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
end

local PENDING_TTL = 30 * 86400
local CLAIM_HEARD = 20   -- seconds an officer has to apply a re-sent claim before its list counts as an answer

-- Account-wide like accountChars, tagged with the guild: the keys only mean something there.
function AltAutoDetect:_KeepPending(mainKey, alts)
    if not GuildOSDB then return end
    GuildOSDB.altPending = GuildOSDB.altPending or {}
    local group = { mainKey }
    for _, k in ipairs(alts) do group[#group + 1] = k end
    GuildOSDB.altPending[GroupSignature(group)] = {
        main = mainKey, alts = alts, guild = GetGuildInfo("player"), ts = GetServerTime(),
    }
end

-- Each pending claim of this guild, after dropping the ones past their time.
function AltAutoDetect:_EachPending(fn)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local guild, now = GetGuildInfo("player"), GetServerTime()
    for sig, p in pairs(pending) do
        if type(p) ~= "table" or not p.main or type(p.alts) ~= "table" or now - (p.ts or 0) > PENDING_TTL then
            pending[sig] = nil
        elseif p.guild == guild then
            fn(sig, p)
        end
    end
end

local function carries(links, p)
    if links[p.main] ~= nil then return false end
    for _, k in ipairs(p.alts) do
        if links[k] ~= p.main then return false end
    end
    return true
end

-- An officer's list just replaced ours. A claim it carries is done; one it lacks goes back
-- on our view and to the officers again, once a session each (an officer is online now).
function AltAutoDetect:OnOfficerLinks()
    if GuildOS:IsOfficer() then return end
    self._resentAt = self._resentAt or {}
    local t = GetTime()
    self:_EachPending(function(sig, p)
        local resentAt = self._resentAt[sig]
        if carries(GuildOS.db.altLinks or {}, p) then
            GuildOSDB.altPending[sig] = nil
        elseif resentAt and t - resentAt > CLAIM_HEARD then
            -- Sent this session and an officer's list still lacks it a while later: the officers
            -- heard it and undid it (an unlink since), and their word stands.
            GuildOSDB.altPending[sig] = nil
        else
            local group = { p.main }
            for _, k in ipairs(p.alts) do group[#group + 1] = k end
            GuildOS.db.altLinks = self:PlanGroup(GuildOS.db.altLinks, group, p.main)
            if not resentAt then
                self._resentAt[sig] = t
                self:_SendClaim(p.main, p.alts)
            end
        end
    end)
end

-- At login: an officer now on this account applies its own claims; a member sends them again.
function AltAutoDetect:ResendPending()
    self:_EachPending(function(sig, p)
        if GuildOS:IsOfficer() then
            local group = { p.main }
            for _, k in ipairs(p.alts) do group[#group + 1] = k end
            self:LinkOwnAlts(p.main, group)
            GuildOSDB.altPending[sig] = nil
        else
            -- Not marked as re-sent: nobody may be online to hear it, and only a re-send made
            -- once an officer's list arrived starts the wait for their answer.
            self:_SendClaim(p.main, p.alts)
        end
    end)
end

-- A member's own unlink takes that character out of any claim still waiting; a claim left with no
-- alt, or about the character as its main, goes.
function AltAutoDetect:_UnclaimPending(key)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local rewrite = {}   -- kept after the walk: a new key added during pairs() is undefined in Lua
    for sig, p in pairs(pending) do
        if type(p) ~= "table" or p.main == key or type(p.alts) ~= "table" then
            if type(p) ~= "table" or p.main == key then pending[sig] = nil end
        else
            local alts = {}
            for _, k in ipairs(p.alts) do if k ~= key then alts[#alts + 1] = k end end
            if #alts < #p.alts then
                pending[sig] = nil
                if #alts > 0 then rewrite[#rewrite + 1] = { main = p.main, alts = alts, guild = p.guild, ts = p.ts } end
            end
        end
    end
    -- Same guild and age as the claim it came from: an unlink here neither moves another guild's
    -- claim into this one nor restarts its thirty days.
    for _, r in ipairs(rewrite) do
        local group = { r.main }
        for _, k in ipairs(r.alts) do group[#group + 1] = k end
        pending[GroupSignature(group)] = r
    end
end

-- A member's re-main replaces any claim waiting about the group's characters with the new one.
function AltAutoDetect:_DropPendingWith(keys)
    local pending = GuildOSDB and GuildOSDB.altPending
    if not pending then return end
    local hit = {}
    for _, k in ipairs(keys) do hit[k] = true end
    for sig, p in pairs(pending) do
        local touches = type(p) ~= "table" or hit[p.main]
        if not touches and type(p.alts) == "table" then
            for _, k in ipairs(p.alts) do if hit[k] then touches = true; break end end
        end
        if touches then pending[sig] = nil end
    end
end

-- Member-safe "set which of my chars is the main". Officers apply directly
-- via the authoritative SetMain; members re-point their OWN group LOCALLY (so
-- their view updates immediately) and broadcast a SELF_ALT self-claim
-- { main = newMainKey, alts = <every other current group member> } that
-- officers replay. Security: the broadcast rides the comm envelope, and
-- HandleSelfClaim only applies a claim whose sender is part of the named
-- group, so a member can only ever re-main a group they belong to.
function AltAutoDetect:SetOwnMain(newMainKey)
    if not newMainKey then return end
    if GuildOS:IsOfficer() then
        GuildOS:SetMain(newMainKey)
        return
    end
    local links = GuildOS.db.altLinks or {}
    local group = GuildOS:GetLinkedChars(newMainKey)
    if #group < 2 then return end               -- nothing to re-main
    if links[newMainKey] == nil then return end -- already the main, no-op
    self:_DropPendingWith(group)
    GuildOS.db.altLinks = GuildOS:_RepointGroup(links, group, newMainKey)
    if GuildOS.CommSystem then
        local alts = {}
        for _, k in ipairs(group) do
            if k ~= newMainKey then alts[#alts + 1] = k end
        end
        local payload = LibSerialize:Serialize({ main = newMainKey, alts = alts })
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
        self:_KeepPending(newMainKey, alts)   -- kept like an accepted prompt, until an officer's list has it
    end
end

-- Member-safe unlink of one's OWN alt: officers apply directly, members
-- broadcast a self-claim that officers replay.
function AltAutoDetect:UnlinkOwnAlt(altKey)
    if not altKey then return end
    if GuildOS:IsOfficer() then
        GuildOS:UnlinkAlt(altKey)
    else
        GuildOS.db.altLinks = GuildOS.db.altLinks or {}
        self:_UnclaimPending(altKey)
        GuildOS.db.altLinks[altKey] = nil
        if GuildOS.CommSystem then
            local payload = LibSerialize:Serialize({ unlink = { altKey } })
            GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
        end
    end
end

-- Officer applies a member's self-claim through the authoritative LinkAlt/
-- UnlinkAlt path. Link and unlink are validated and handled independently so
-- an unlink-only claim (no main/alts) isn't rejected by the link guard.
-- Security: a claim is only ever trusted for the KEYS IT NAMES about the
-- SENDER themselves — the sender's own player key is derived from the comm
-- envelope (never taken from the claim body), so a member cannot forge a
-- claim that links/unlinks someone else's characters.
function AltAutoDetect:HandleSelfClaim(sender, data)
    if not GuildOS:IsOfficer() then return end       -- only officers apply/propagate
    local ok, claim = LibSerialize:Deserialize(data)
    if not ok or type(claim) ~= "table" then return end

    local sShort = sender and (sender:match("^([^-]+)") or sender)
    if not sShort then return end
    local sRealm = (sender:match("-(.+)$")) or GetRealmName()
    local senderKey = GuildOS:GetPlayerKey(sShort, sRealm)
    -- The claim's keys were built on the sender's client: as this client keys them (#97).
    if claim.main then claim.main = GuildOS:LocalMemberKey(claim.main) end
    if type(claim.alts) == "table" then
        for i, k in ipairs(claim.alts) do claim.alts[i] = GuildOS:LocalMemberKey(k) end
    end
    if type(claim.unlink) == "table" then
        for i, k in ipairs(claim.unlink) do claim.unlink[i] = GuildOS:LocalMemberKey(k) end
    end

    if claim.main and type(claim.alts) == "table" then
        -- Only apply if the sender is part of the group they're claiming
        -- (either the main or one of the alts) — never someone else's.
        local involvesSender = (claim.main == senderKey)
        if not involvesSender then
            for _, k in ipairs(claim.alts) do
                if k == senderKey then involvesSender = true; break end
            end
        end
        if involvesSender then
            -- The claim asserts claim.main is THE main. If it is currently an
            -- alt of someone else, clear its own entry BEFORE the LinkAlt loop
            -- so LinkAlt's circular guard (mainKey must not itself be an alt)
            -- does not reject promoting an existing alt to main.
            --
            -- BUT clear ONLY when claim.main is already in the SENDER's own
            -- group. Otherwise a claim {main=X, alts={self}} with an unrelated X
            -- would detach X from its real group. When not same-group we skip
            -- the clear, and LinkAlt's circular guard still blocks linking to an
            -- existing alt, so a member can only re-main a group they belong to.
            GuildOS.db.altLinks = GuildOS.db.altLinks or {}
            local senderGroup = GuildOS:GetLinkedChars(senderKey)
            for _, k in ipairs(senderGroup) do
                if k == claim.main then GuildOS.db.altLinks[claim.main] = nil; break end
            end
            for _, k in ipairs(claim.alts) do
                if k ~= claim.main then GuildOS:LinkAlt(k, claim.main) end
            end
        end
    end
    if type(claim.unlink) == "table" then
        -- Only unlink a key the sender owns: themselves, or an alt whose
        -- main is the sender.
        for _, k in ipairs(claim.unlink) do
            local links = GuildOS.db.altLinks or {}
            if k == senderKey or links[k] == senderKey then
                GuildOS:UnlinkAlt(k)
            end
        end
    end
end

----------------------------------------------------------------------
-- Login suggestion prompt: "Link N chars as alts of [Main]?"
-- Suggest + one-click confirm. Nagging is guarded two ways: at most once
-- per session, and a persisted per-group "declined" marker so a login
-- doesn't re-offer the exact same group forever (a new/removed alt changes
-- the signature and is re-offered).
----------------------------------------------------------------------
function AltAutoDetect:_RegisterPopup()
    if GuildOS.Dialogs["GUILDOS_ALT_AUTODETECT"] then return end
    GuildOS.Dialogs["GUILDOS_ALT_AUTODETECT"] = {
        text = L["Found %d of your characters in this guild. Link them as alts of %s?"],
        button1 = L["Link"],
        button2 = L["Not now"],
        OnAccept = function(dlg, data)
            local r = data or (dlg and dlg.data)
            if not r then return end
            if AltAutoDetect:LinkOwnAlts(r.main, r.group) > 0 then
                local short = r.main:match("^([^-]+)") or r.main
                GuildOS:Print(string.format(L["Linked %d alt(s) to %s."], #r.group - 1, short))
            end
        end,
        OnCancel = function(dlg, data)
            local r = data or (dlg and dlg.data)
            if not r then return end
            GuildOSDB.altDeclined = GuildOSDB.altDeclined or {}
            GuildOSDB.altDeclined[GroupSignature(r.group)] = true
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- Shows the confirm popup for a detected group `r` ({ group = {keys...}, main = key }).
-- `r` is passed through the dialog's text/data args rather than captured
-- by closure, so a stale `r` from an earlier scan can never be shown/applied.
function AltAutoDetect:_ShowPrompt(r)
    self:_RegisterPopup()
    local short = r.main:match("^([^-]+)") or r.main
    local dlg = GuildOS:ShowDialog("GUILDOS_ALT_AUTODETECT", #r.group - 1, short, r)
    if dlg then dlg.data = r end
    self._prompted = true
end

-- Called from Initialize, after the roster has had time to populate
-- (cold-login timing — GetGuildRosterInfo is empty for the first few
-- seconds after login).
function AltAutoDetect:_SchedulePrompt()
    GuildOS.Compat.After(10, function()
        AltAutoDetect:ResendPending()
        if AltAutoDetect._prompted then return end
        local r = AltAutoDetect:DetectOwnAlts(GuildOSDB.accountChars, AltAutoDetect:_GuildSet(), GuildOS.db.altLinks)
        if not r then return end
        local declined = GuildOSDB.altDeclined
        if declined and declined[GroupSignature(r.group)] then return end
        AltAutoDetect:_ShowPrompt(r)
    end)
end

-- Manual trigger for /gos myalts: ignores the session/declined guards.
function AltAutoDetect:PromptNow()
    local r = self:DetectOwnAlts(GuildOSDB.accountChars, self:_GuildSet(), GuildOS.db.altLinks)
    if r then
        self:_ShowPrompt(r)
    else
        GuildOS:Print(L["No other characters of yours found in this guild."])
    end
end

function AltAutoDetect:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    -- Keyed the way this client keys: on WoW: Forever any other realm is rewritten to its own (#97).
    local main, alt, other = GuildOS:GetPlayerKey("Main"), GuildOS:GetPlayerKey("Alt"), GuildOS:GetPlayerKey("Other")
    local acc = { [main] = { level = 70 }, [alt] = { level = 61 }, [other] = { level = 70 } }
    local guild = { [main] = true, [alt] = true }   -- Other not in this guild
    S:Register("altauto.detect", function()
        local r = AltAutoDetect:DetectOwnAlts(acc, guild, {})
        if not r or r.main ~= main then return false, "main=highest level in guild" end
        if #r.group ~= 2 then return false, "only guild members grouped" end
        return true
    end)
    S:Register("altauto.needs_two", function()
        if AltAutoDetect:DetectOwnAlts(acc, { [main] = true }, {}) ~= nil then return false, "need 2+" end
        return true
    end)
    S:Register("altauto.already_linked", function()
        if AltAutoDetect:DetectOwnAlts(acc, guild, { [alt] = main }) ~= nil then
            return false, "already linked => nil"
        end
        return true
    end)
end
