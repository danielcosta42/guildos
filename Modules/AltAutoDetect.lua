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
    local key = GuildOS:GetPlayerKey(name, GetRealmName())
    local _, classFile = UnitClass("player")
    GuildOSDB.accountChars[key] = {
        name = name, realm = GetRealmName(), class = classFile,
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

-- Pure: from the account chars that are ALSO current guild members, if 2+
-- exist and they are not already all linked under one main, return the group
-- and the suggested main (highest level). Else nil.
function AltAutoDetect:DetectOwnAlts(accountChars, guildSet, altLinks)
    altLinks = altLinks or {}
    local group = {}
    for key, info in pairs(accountChars or {}) do
        local lk = GuildOS:LocalMemberKey(key)   -- recorded on another realm's client (#97)
        if guildSet[lk] then group[#group + 1] = { key = lk, level = info.level or 0 } end
    end
    if #group < 2 then return nil end
    table.sort(group, function(a, b) return a.level > b.level end)
    local main = group[1].key
    -- already fully linked to this main?
    local allLinked = true
    for i = 2, #group do
        if altLinks[group[i].key] ~= main then allLinked = false; break end
    end
    if allLinked then return nil end
    local keys = {}
    for _, g in ipairs(group) do keys[#keys + 1] = g.key end
    return { group = keys, main = main }
end

function AltAutoDetect:LinkOwnAlts(mainKey, altKeys)
    if not mainKey or not altKeys then return end
    if GuildOS:IsOfficer() then
        -- authoritative path: LinkAlt writes db.altLinks + BroadcastAltLinks
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then GuildOS:LinkAlt(k, mainKey) end
        end
    else
        -- member: apply locally (own view) + broadcast a self-claim officers replay
        GuildOS.db.altLinks = GuildOS.db.altLinks or {}
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then GuildOS.db.altLinks[k] = mainKey end
        end
        if GuildOS.CommSystem then
            local payload = LibSerialize:Serialize({ main = mainKey, alts = altKeys })
            GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
        end
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
    GuildOS.db.altLinks = GuildOS:_RepointGroup(links, group, newMainKey)
    if GuildOS.CommSystem then
        local alts = {}
        for _, k in ipairs(group) do
            if k ~= newMainKey then alts[#alts + 1] = k end
        end
        local payload = LibSerialize:Serialize({ main = newMainKey, alts = alts })
        GuildOS.CommSystem:SendMessage(GuildOS.CommSystem.MSG_TYPES.SELF_ALT, payload)
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
    if StaticPopupDialogs["GUILDOS_ALT_AUTODETECT"] then return end
    StaticPopupDialogs["GUILDOS_ALT_AUTODETECT"] = {
        text = L["Found %d of your characters in this guild. Link them as alts of %s?"],
        button1 = L["Link"],
        button2 = L["Not now"],
        OnAccept = function(dlg, data)
            local r = data or (dlg and dlg.data)
            if not r then return end
            AltAutoDetect:LinkOwnAlts(r.main, r.group)
            local short = r.main:match("^([^-]+)") or r.main
            GuildOS:Print(string.format(L["Linked %d alt(s) to %s."], #r.group - 1, short))
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
-- `r` is passed through StaticPopup_Show's text/data args rather than captured
-- by closure, so a stale `r` from an earlier scan can never be shown/applied.
function AltAutoDetect:_ShowPrompt(r)
    self:_RegisterPopup()
    local short = r.main:match("^([^-]+)") or r.main
    local dlg = StaticPopup_Show("GUILDOS_ALT_AUTODETECT", #r.group - 1, short, r)
    if dlg then dlg.data = r end
    self._prompted = true
end

-- Called from Initialize, after the roster has had time to populate
-- (cold-login timing — GetGuildRosterInfo is empty for the first few
-- seconds after login).
function AltAutoDetect:_SchedulePrompt()
    GuildOS.Compat.After(10, function()
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
