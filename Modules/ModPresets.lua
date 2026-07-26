----------------------------------------------------------------------
-- Guild OS - Moderation Presets (Leadership Suite)
-- Built-in bulk-moderation preset TYPES with adjustable thresholds:
--   * purge_inactive   -- inactive too long AND at/below a rank
--   * promote_regulars -- strong raid attendance
--   * trial_cleanup    -- long-running trials with weak attendance
-- Business logic only, no UI frames (Rule 2 / Rule 10). The pure matchers
-- take an explicit member list so self-tests pin them without a live roster.
-- Apply routes every action through GuildManager, whose rank/kick handoffs
-- are Blizzard-protected (they open the native guild panel; ADR-0010). This
-- module NEVER calls a protected guild API directly.
----------------------------------------------------------------------
local ModPresets = {}
BRutus.ModPresets = ModPresets
local L = BRutus.L

-- Built-in preset TYPES. `defaults` seeds a new instance's thresholds;
-- `action` picks the GuildManager handoff Apply uses ("kick" / "promote").
ModPresets.TYPES = {
    purge_inactive = {
        name     = L["Purge inactive"],
        defaults = { days = 30, minRankIndex = 4 },
        action   = "kick",
    },
    promote_regulars = {
        name     = L["Promote regulars"],
        defaults = { minAttendance = 90 },
        action   = "promote",
    },
    trial_cleanup = {
        name     = L["Trial cleanup"],
        defaults = { minDays = 14, maxAttendance = 50 },
        action   = "kick",
    },
}

-- Stable order for seeding + the "+ New" chooser.
ModPresets.TYPE_ORDER = { "purge_inactive", "promote_regulars", "trial_cleanup" }

----------------------------------------------------------------------
-- Init + model (db.modPresets = list of { type, name, thresholds = {...} })
----------------------------------------------------------------------
function ModPresets:Initialize()
    if BRutus.db.modPresets == nil then
        BRutus.db.modPresets = {}
        for _, key in ipairs(self.TYPE_ORDER) do
            self:_AppendDefault(key)
        end
    end
    self:_RegisterTests()
end

-- Append a fresh instance of a built-in type with a COPY of its defaults.
function ModPresets:_AppendDefault(typeKey)
    local t = self.TYPES[typeKey]
    if not t then return end
    BRutus.db.modPresets = BRutus.db.modPresets or {}
    local th = {}
    for k, v in pairs(t.defaults) do th[k] = v end
    table.insert(BRutus.db.modPresets, { type = typeKey, name = t.name, thresholds = th })
end

function ModPresets:GetPresets()
    return BRutus.db.modPresets or {}
end

function ModPresets:GetAction(preset)
    local t = preset and self.TYPES[preset.type]
    return (t and t.action) or "kick"
end

-- Officer-gated mutations (Rule: officer-only actions).
function ModPresets:AddPreset(typeKey)
    if not BRutus:IsOfficer() then BRutus:Print(L["Officers only."]) return false end
    if not self.TYPES[typeKey] then return false end
    self:_AppendDefault(typeKey)
    return true
end

function ModPresets:RemovePreset(index)
    if not BRutus:IsOfficer() then BRutus:Print(L["Officers only."]) return false end
    local list = BRutus.db.modPresets
    if list and list[index] then
        table.remove(list, index)
        return true
    end
    return false
end

function ModPresets:SetThreshold(index, key, value)
    if not BRutus:IsOfficer() then return false end
    local p = BRutus.db.modPresets and BRutus.db.modPresets[index]
    if not p or not key then return false end
    value = tonumber(value)
    if not value then return false end
    if value < 0 then value = 0 end
    p.thresholds = p.thresholds or {}
    p.thresholds[key] = math.floor(value)
    return true
end

-- One-line criteria summary shown beside the preset name.
function ModPresets:Summarize(preset)
    local th = (preset and preset.thresholds) or {}
    if preset.type == "purge_inactive" then
        local rn = (BRutus.GuildManager and BRutus.GuildManager:GetRankName(th.minRankIndex or 0)) or "?"
        return format(L["inactive >= %dd, rank <= %s"], th.days or 0, rn)
    elseif preset.type == "promote_regulars" then
        return format(L["attendance >= %d%%"], th.minAttendance or 0)
    elseif preset.type == "trial_cleanup" then
        return format(L["trial, joined >= %dd, attendance < %d%%"], th.minDays or 0, th.maxAttendance or 0)
    end
    return ""
end

----------------------------------------------------------------------
-- PURE matchers (deterministic; unit-tested via /gos selftest).
-- Each takes an explicit member list + thresholds and returns the subset
-- that matches. No roster / db access here.
----------------------------------------------------------------------
-- Offline for at least `days` AND rankIndex at/below `minRankIndex`
-- (higher index = lower privilege, so >= protects officers / the GM).
function ModPresets:_MatchInactive(members, days, minRankIndex)
    local out = {}
    for _, m in ipairs(members) do
        if (m.daysOffline or 0) >= days and (m.rankIndex or 0) >= minRankIndex then
            out[#out + 1] = m
        end
    end
    return out
end

-- Attendance at or above `minAttendance` percent.
function ModPresets:_MatchPromote(members, minAttendance)
    local out = {}
    for _, m in ipairs(members) do
        if (m.attendance or 0) >= minAttendance then
            out[#out + 1] = m
        end
    end
    return out
end

-- Trials started at least `minDays` ago AND attendance strictly below
-- `maxAttendance` percent.
function ModPresets:_MatchTrialCleanup(members, minDays, maxAttendance)
    local out = {}
    for _, m in ipairs(members) do
        if (m.daysSince or 0) >= minDays and (m.attendance or 0) < maxAttendance then
            out[#out + 1] = m
        end
    end
    return out
end

----------------------------------------------------------------------
-- Live member-list resolvers (impure; reuse the existing data sources).
----------------------------------------------------------------------
-- Non-officer, non-trial roster members with their 25-man attendance.
-- Mirrors GuildManager:GetSuggestions' population but WITHOUT the fixed
-- attendance floor, so the preset threshold is authoritative.
function ModPresets:_CollectPromotable()
    local out = {}
    if not BRutus.RaidTracker then return out end
    local officerMaxRank = BRutus:GetSetting("officerMaxRank") or 1
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rankName, rankIndex, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if name then
            local short = name:match("^([^-]+)") or name
            local realm = name:match("-(.+)$") or GetRealmName()
            local key = BRutus:GetPlayerKey(short, realm)
            local isTrial = BRutus.TrialTracker and BRutus.TrialTracker:IsTrial(key)
            local isOfficer = rankIndex and rankIndex <= officerMaxRank
            if not isTrial and not isOfficer then
                out[#out + 1] = {
                    name       = short,
                    fullName   = name,
                    rankName   = rankName,
                    rankIndex  = rankIndex,
                    class      = classFile or "",
                    attendance = BRutus.RaidTracker:GetAttendance25ManPercent(key) or 0,
                }
            end
        end
    end
    return out
end

-- Active trials with days-since-start and 25-man attendance.
function ModPresets:_CollectTrials()
    local out = {}
    if not BRutus.TrialTracker then return out end
    for _, t in ipairs(BRutus.TrialTracker:GetActiveTrials()) do
        local key = t.key
        local short = key:match("^([^-]+)") or key
        local att = (BRutus.RaidTracker and BRutus.RaidTracker:GetAttendance25ManPercent(key)) or 0
        out[#out + 1] = {
            name       = short,
            fullName   = key,
            daysSince  = BRutus.TrialTracker:GetDaysSinceStart(key) or 0,
            attendance = att,
        }
    end
    return out
end

----------------------------------------------------------------------
-- GetMatches — resolve the live member list for a preset and run its
-- matcher. Returns UI rows { name, fullName, detail }.
----------------------------------------------------------------------
function ModPresets:GetMatches(preset)
    if not preset then return {} end
    local th = preset.thresholds or {}

    if preset.type == "purge_inactive" then
        local days = th.days or 0
        local members = (BRutus.GuildManager and BRutus.GuildManager:GetInactiveMembers(days)) or {}
        local matched = self:_MatchInactive(members, days, th.minRankIndex or 0)
        local out = {}
        for _, m in ipairs(matched) do
            local rn = (BRutus.GuildManager and BRutus.GuildManager:GetRankName(m.rankIndex)) or "?"
            out[#out + 1] = {
                name     = m.name,
                fullName = m.fullName,
                detail   = (m.daysOffline or 0) .. L["d offline"] .. "  " .. rn,
            }
        end
        return out

    elseif preset.type == "promote_regulars" then
        local matched = self:_MatchPromote(self:_CollectPromotable(), th.minAttendance or 0)
        local out = {}
        for _, m in ipairs(matched) do
            out[#out + 1] = {
                name     = m.name,
                fullName = m.fullName,
                detail   = format(L["%d%% attendance"], m.attendance or 0),
            }
        end
        return out

    elseif preset.type == "trial_cleanup" then
        local matched = self:_MatchTrialCleanup(self:_CollectTrials(), th.minDays or 0, th.maxAttendance or 0)
        local out = {}
        for _, m in ipairs(matched) do
            out[#out + 1] = {
                name     = m.name,
                fullName = m.fullName,
                detail   = format(L["day %d, %d%% att"], m.daysSince or 0, m.attendance or 0),
            }
        end
        return out
    end

    return {}
end

----------------------------------------------------------------------
-- Apply — act on the matched members. Officer-gated. Rank changes and
-- kicks are Blizzard-protected, so each is handed off to GuildManager,
-- which opens the native guild panel for the officer to confirm. This
-- function performs NO protected call itself (ADR-0010).
----------------------------------------------------------------------
function ModPresets:ApplyPreset(preset, matches)
    if not BRutus:IsOfficer() then BRutus:Print(L["Officers only."]) return false end
    if not preset then return false end
    matches = matches or self:GetMatches(preset)
    if #matches == 0 then return false end
    local GM = BRutus.GuildManager
    if not GM then return false end
    local action = self:GetAction(preset)
    for _, m in ipairs(matches) do
        if action == "promote" then
            GM:Promote(m.fullName)
        else
            GM:ConfirmKick(m.fullName)
        end
    end
    GM:RefreshUI()
    return true
end

----------------------------------------------------------------------
-- Self-tests (pure matchers only; boundary cases at / just inside / just
-- outside each threshold). Injected member lists, never the live roster.
----------------------------------------------------------------------
function ModPresets:_RegisterTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("modpresets.inactive_boundary", function()
        local members = {
            { name = "A", rankIndex = 4, daysOffline = 30 },  -- at both -> match
            { name = "B", rankIndex = 9, daysOffline = 29 },  -- below days -> no
            { name = "C", rankIndex = 3, daysOffline = 45 },  -- rank too senior -> no
            { name = "D", rankIndex = 5, daysOffline = 31 },  -- inside -> match
        }
        local out = ModPresets:_MatchInactive(members, 30, 4)
        if #out ~= 2 then return false, "expected 2, got " .. #out end
        if out[1].name ~= "A" or out[2].name ~= "D" then return false, "wrong subset" end
        return true
    end)

    S:Register("modpresets.promote_boundary", function()
        local members = {
            { name = "A", attendance = 90 },  -- at threshold -> match
            { name = "B", attendance = 89 },  -- just outside -> no
            { name = "C", attendance = 91 },  -- inside -> match
        }
        local out = ModPresets:_MatchPromote(members, 90)
        if #out ~= 2 then return false, "expected 2, got " .. #out end
        if out[1].name ~= "A" or out[2].name ~= "C" then return false, "wrong subset" end
        return true
    end)

    S:Register("modpresets.trial_boundary", function()
        local members = {
            { name = "A", daysSince = 14, attendance = 49 },  -- both inside -> match
            { name = "B", daysSince = 14, attendance = 50 },  -- att not < 50 -> no
            { name = "C", daysSince = 13, attendance = 10 },  -- days outside -> no
            { name = "D", daysSince = 20, attendance = 49 },  -- inside -> match
        }
        local out = ModPresets:_MatchTrialCleanup(members, 14, 50)
        if #out ~= 2 then return false, "expected 2, got " .. #out end
        if out[1].name ~= "A" or out[2].name ~= "D" then return false, "wrong subset" end
        return true
    end)
end
