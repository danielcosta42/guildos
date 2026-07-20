----------------------------------------------------------------------
-- Guild OS - Alt Auto-Detect
-- Detects the player's own same-account characters via the account-wide
-- SavedVariables (GuildOSDB is shared across all chars on the game account)
-- and offers a one-click link. Own alts only; others' alts are never
-- auto-detectable (no API reveals another player's account).
----------------------------------------------------------------------
local AltAutoDetect = {}
BRutus.AltAutoDetect = AltAutoDetect

local L = BRutus.L
local LibSerialize = LibStub("LibSerialize")

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
    local name = UnitName("player")
    if not name then return end
    local key = BRutus:GetPlayerKey(name, GetRealmName())
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
            set[BRutus:GetPlayerKey(short, realm)] = true
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
        if guildSet[key] then group[#group + 1] = { key = key, level = info.level or 0 } end
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
    if BRutus:IsOfficer() then
        -- authoritative path: LinkAlt writes db.altLinks + BroadcastAltLinks
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then BRutus:LinkAlt(k, mainKey) end
        end
    else
        -- member: apply locally (own view) + broadcast a self-claim officers replay
        BRutus.db.altLinks = BRutus.db.altLinks or {}
        for _, k in ipairs(altKeys) do
            if k ~= mainKey then BRutus.db.altLinks[k] = mainKey end
        end
        if BRutus.CommSystem then
            local payload = LibSerialize:Serialize({ main = mainKey, alts = altKeys })
            BRutus.CommSystem:SendMessage(BRutus.CommSystem.MSG_TYPES.SELF_ALT, payload)
        end
    end
end

-- Officer applies a member's self-claim through the authoritative LinkAlt path.
function AltAutoDetect:HandleSelfClaim(_sender, data)
    if not BRutus:IsOfficer() then return end       -- only officers apply/propagate
    local ok, claim = LibSerialize:Deserialize(data)
    if not ok or type(claim) ~= "table" or not claim.main or type(claim.alts) ~= "table" then return end
    for _, k in ipairs(claim.alts) do
        if k ~= claim.main then BRutus:LinkAlt(k, claim.main) end
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
            BRutus:Print(string.format(L["Linked %d alt(s) to %s."], #r.group - 1, short))
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
    BRutus.Compat.After(10, function()
        if AltAutoDetect._prompted then return end
        local r = AltAutoDetect:DetectOwnAlts(GuildOSDB.accountChars, AltAutoDetect:_GuildSet(), BRutus.db.altLinks)
        if not r then return end
        local declined = GuildOSDB.altDeclined
        if declined and declined[GroupSignature(r.group)] then return end
        AltAutoDetect:_ShowPrompt(r)
    end)
end

-- Manual trigger for /gos myalts: ignores the session/declined guards.
function AltAutoDetect:PromptNow()
    local r = self:DetectOwnAlts(GuildOSDB.accountChars, self:_GuildSet(), BRutus.db.altLinks)
    if r then
        self:_ShowPrompt(r)
    else
        BRutus:Print(L["No other characters of yours found in this guild."])
    end
end

function AltAutoDetect:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest
    local acc = {
        ["Main-R"] = { level = 70 }, ["Alt-R"] = { level = 61 }, ["Other-R"] = { level = 70 },
    }
    local guild = { ["Main-R"] = true, ["Alt-R"] = true }   -- Other-R not in this guild
    S:Register("altauto.detect", function()
        local r = AltAutoDetect:DetectOwnAlts(acc, guild, {})
        if not r or r.main ~= "Main-R" then return false, "main=highest level in guild" end
        if #r.group ~= 2 then return false, "only guild members grouped" end
        return true
    end)
    S:Register("altauto.needs_two", function()
        if AltAutoDetect:DetectOwnAlts(acc, { ["Main-R"] = true }, {}) ~= nil then return false, "need 2+" end
        return true
    end)
    S:Register("altauto.already_linked", function()
        if AltAutoDetect:DetectOwnAlts(acc, guild, { ["Alt-R"] = "Main-R" }) ~= nil then
            return false, "already linked => nil"
        end
        return true
    end)
end
