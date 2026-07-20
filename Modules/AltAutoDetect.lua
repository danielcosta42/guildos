----------------------------------------------------------------------
-- Guild OS - Alt Auto-Detect
-- Detects the player's own same-account characters via the account-wide
-- SavedVariables (GuildOSDB is shared across all chars on the game account)
-- and offers a one-click link. Own alts only; others' alts are never
-- auto-detectable (no API reveals another player's account).
----------------------------------------------------------------------
local AltAutoDetect = {}
BRutus.AltAutoDetect = AltAutoDetect

local LibSerialize = LibStub("LibSerialize")

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
