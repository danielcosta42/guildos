----------------------------------------------------------------------
-- Guild OS - Moderation Presets (Leadership Suite)
-- Built-in bulk-moderation preset TYPES with adjustable thresholds:
--   * purge_inactive   -- inactive too long AND at/below a rank
--   * promote_regulars -- strong raid attendance
--   * trial_cleanup    -- long-running trials with weak attendance
-- Business logic only, no UI frames (Rule 2 / Rule 10). Each preset is a saved
-- Bulk actions rule set (audit B8): it matches through BulkActions.Match (the
-- safe list, the rank limits, an unknown attendance meeting no attendance
-- rule) and Apply queues it in Bulk actions, one click of Next per member.
-- This module NEVER calls a protected guild API directly.
----------------------------------------------------------------------
local ModPresets = {}
GuildOS.ModPresets = ModPresets
local L = GuildOS.L

-- The attendance (%) that makes a regular worth promoting: the promote preset's default, and what Suggestions
-- read (PromoteAttendance), where it was 80 and the preset 90 (audit B8).
ModPresets.PROMOTE_ATTENDANCE = 80

-- Built-in preset TYPES. `defaults` seeds a new instance's thresholds;
-- `action` is the Bulk actions queue Apply starts ("remove" / "promote").
ModPresets.TYPES = {
    purge_inactive = {
        name     = L["Purge inactive"],
        defaults = { days = 30, minRankIndex = 4 },
        action   = "remove",
    },
    promote_regulars = {
        name     = L["Promote regulars"],
        defaults = { minAttendance = ModPresets.PROMOTE_ATTENDANCE },
        action   = "promote",
    },
    trial_cleanup = {
        name     = L["Trial cleanup"],
        defaults = { minDays = 14, maxAttendance = 50 },
        action   = "remove",
    },
}

-- Stable order for seeding + the "+ New" chooser.
ModPresets.TYPE_ORDER = { "purge_inactive", "promote_regulars", "trial_cleanup" }

----------------------------------------------------------------------
-- Init + model (db.modPresets = list of { type, name, thresholds = {...} })
----------------------------------------------------------------------
function ModPresets:Initialize()
    if GuildOS.db.modPresets == nil then
        GuildOS.db.modPresets = {}
        for _, key in ipairs(self.TYPE_ORDER) do
            self:_AppendDefault(key)
        end
    end
    -- The old default of 90% becomes the one threshold Suggestions use too (audit B8), once.
    if not GuildOS.db.modPresetsB8 then
        GuildOS.db.modPresetsB8 = true
        for _, p in ipairs(GuildOS.db.modPresets) do
            if p.type == "promote_regulars" and p.thresholds and p.thresholds.minAttendance == 90 then
                p.thresholds.minAttendance = self.PROMOTE_ATTENDANCE
            end
        end
    end
    self:_RegisterTests()
end

-- Append a fresh instance of a built-in type with a COPY of its defaults.
function ModPresets:_AppendDefault(typeKey)
    local t = self.TYPES[typeKey]
    if not t then return end
    GuildOS.db.modPresets = GuildOS.db.modPresets or {}
    local th = {}
    for k, v in pairs(t.defaults) do th[k] = v end
    table.insert(GuildOS.db.modPresets, { type = typeKey, name = t.name, thresholds = th })
end

function ModPresets:GetPresets()
    return GuildOS.db.modPresets or {}
end

-- A built-in preset reads in the language of now: the name it was saved with is the language
-- it was created in, English for every guild seeded before its translation (issue #114).
function ModPresets:Name(preset)
    local t = preset and self.TYPES[preset.type]
    return (t and t.name) or (preset and preset.name) or "?"
end

function ModPresets:GetAction(preset)
    local t = preset and self.TYPES[preset.type]
    return (t and t.action) or "remove"
end

-- Officer-gated mutations (Rule: officer-only actions).
function ModPresets:AddPreset(typeKey)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Officers only."]) return false end
    if not self.TYPES[typeKey] then return false end
    self:_AppendDefault(typeKey)
    return true
end

function ModPresets:RemovePreset(index)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Officers only."]) return false end
    local list = GuildOS.db.modPresets
    if list and list[index] then
        table.remove(list, index)
        return true
    end
    return false
end

function ModPresets:SetThreshold(index, key, value)
    if not GuildOS:IsOfficer() then return false end
    local p = GuildOS.db.modPresets and GuildOS.db.modPresets[index]
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
        local rn = (GuildOS.GuildManager and GuildOS.GuildManager:GetRankName(th.minRankIndex or 0)) or "?"
        return format(L["inactive >= %dd, rank <= %s"], th.days or 0, rn)
    elseif preset.type == "promote_regulars" then
        return format(L["attendance >= %d%%"], th.minAttendance or 0)
    elseif preset.type == "trial_cleanup" then
        return format(L["trial, joined >= %dd, attendance < %d%%"], th.minDays or 0, th.maxAttendance or 0)
    end
    return ""
end

----------------------------------------------------------------------
-- Audit B8: a preset is a saved Bulk actions rule set. It matches through BulkActions.Match, so it keeps every
-- rule the Bulk tab keeps: never oneself nor a rank at or above one's own (the rank limits), never a member on the
-- safe list in a removal (#429), and an unknown attendance meets no attendance rule (a trial with no raids tracked
-- is no "low attendance" removal). It runs as Bulk actions' queue, one member per click of Next.
----------------------------------------------------------------------
-- The Bulk actions rules a preset stands for (BulkActions.Rules' raw shape), from its thresholds.
function ModPresets.BulkRules(preset)
    local th = (preset and preset.thresholds) or {}
    if preset.type == "purge_inactive" then
        return { days = math.max(1, th.days or 0) }
    elseif preset.type == "promote_regulars" then
        return { attMin = th.minAttendance or ModPresets.PROMOTE_ATTENDANCE }
    elseif preset.type == "trial_cleanup" then
        return { attMax = math.max(0, (th.maxAttendance or 0) - 1) }   -- strictly below the threshold
    end
    return {}
end

-- What a preset asks beyond the Bulk rules, on member `m` (Collect's line, with `trial`, `trialDays` added):
-- the removal of the inactive only at or below its rank; promotion never of a trial or an officer's rank; the
-- trial clean-up only trials running at least its days. Pure.
function ModPresets.Extra(preset, m, officerMaxRank)
    local th = (preset and preset.thresholds) or {}
    if preset.type == "purge_inactive" then
        return (m.rankIndex or 0) >= (th.minRankIndex or 0)
    elseif preset.type == "promote_regulars" then
        return not m.trial and m.rankIndex ~= nil and m.rankIndex > (officerMaxRank or 1)
    elseif preset.type == "trial_cleanup" then
        return m.trial == true and (m.trialDays or 0) >= (th.minDays or 0)
    end
    return false
end

-- The members of `members` the preset touches, through BulkActions.Match with `ctx` (BulkActions:Context()). Pure.
function ModPresets.Match(preset, members, ctx, officerMaxRank)
    local BA = GuildOS.BulkActions
    if not (BA and preset and ModPresets.TYPES[preset.type]) then return {} end
    local action = ModPresets.TYPES[preset.type].action
    local out = {}
    for _, m in ipairs((BA.Match(members, BA.Rules(ModPresets.BulkRules(preset)), action, ctx))) do
        if ModPresets.Extra(preset, m, officerMaxRank) then out[#out + 1] = m end
    end
    return out
end

-- The attendance the promotion suggestions read: the guild's promote preset's, so both say the same (audit B8).
function ModPresets:PromoteAttendance()
    for _, p in ipairs(self:GetPresets()) do
        if p.type == "promote_regulars" and p.thresholds and p.thresholds.minAttendance then
            return p.thresholds.minAttendance
        end
    end
    return self.PROMOTE_ATTENDANCE
end

----------------------------------------------------------------------
-- GetMatches: the live roster (BulkActions:Collect, attendance included) through Match. Rows
-- { name, fullName, key, detail }.
----------------------------------------------------------------------
function ModPresets:GetMatches(preset)
    local BA = GuildOS.BulkActions
    if not (preset and BA) then return {} end
    local TT = GuildOS.TrialTracker
    local members = BA:Collect(true)
    for _, m in ipairs(members) do
        if TT and TT:IsTrial(m.key) then m.trial, m.trialDays = true, TT:GetDaysSinceStart(m.key) or 0 end
    end
    local matched = self.Match(preset, members, BA:Context(), GuildOS:GetSetting("officerMaxRank") or 1)
    local out = {}
    for _, m in ipairs(matched) do
        local detail
        if preset.type == "purge_inactive" then
            detail = (m.daysOffline or 0) .. L["d offline"] .. "  " .. (m.rankName or "?")
        elseif preset.type == "promote_regulars" then
            detail = format(L["%d%% attendance"], m.attendance or 0)
        else
            detail = format(L["day %d, %d%% att"], m.trialDays or 0, m.attendance or 0)
        end
        out[#out + 1] = { name = m.name, fullName = m.fullName, key = m.key, detail = detail }
    end
    return out
end

----------------------------------------------------------------------
-- Apply: the matched members into Bulk actions' queue (one click of Next each, the only way the game takes a rank
-- change or a removal from an addon, ADR-0038). Officer-gated; the panel's confirmation is the officer's yes.
----------------------------------------------------------------------
function ModPresets:ApplyPreset(preset, matches)
    if not GuildOS:IsOfficer() then GuildOS:Print(L["Officers only."]) return false end
    if not preset then return false end
    matches = matches or self:GetMatches(preset)
    if #matches == 0 then return false end
    local BA = GuildOS.BulkActions
    if not BA then return false end
    local keys = {}
    for _, m in ipairs(matches) do keys[#keys + 1] = m.key or GuildOS:KeyOfRosterName(m.fullName or m.name) end
    return BA:StartListAndSay(self:GetAction(preset), BA:ListFor(keys))
end

----------------------------------------------------------------------
-- Self-tests (pure: injected members and context, never the live roster).
----------------------------------------------------------------------
function ModPresets:_RegisterTests()
    if not GuildOS.SelfTest then return end
    local S = GuildOS.SelfTest
    local ctx = { myRank = 1, lowestRank = 9, meKey = "Me" }

    S:Register("modpresets.unknown_attendance", function()
        local p = { type = "trial_cleanup", thresholds = { minDays = 14, maxAttendance = 50 } }
        local members = {
            { key = "A", name = "A", rankIndex = 8, trial = true, trialDays = 20, attendance = 10 },
            { key = "B", name = "B", rankIndex = 8, trial = true, trialDays = 20, attendance = nil },  -- no raid tracked
            { key = "C", name = "C", rankIndex = 8, trial = true, trialDays = 20, attendance = 50 },  -- not below
        }
        local out = ModPresets.Match(p, members, ctx, 1)
        if #out ~= 1 or out[1].key ~= "A" then return false, "only the known low attendance" end
        return true
    end)

    S:Register("modpresets.safe_and_ranks", function()
        local p = { type = "purge_inactive", thresholds = { days = 30, minRankIndex = 4 } }
        local members = {
            { key = "A", name = "A", rankIndex = 5, daysOffline = 40 },
            { key = "S", name = "S", rankIndex = 5, daysOffline = 40, safe = true },   -- on the safe list
            { key = "O", name = "O", rankIndex = 1, daysOffline = 99 },                -- my own rank
            { key = "Me", name = "Me", rankIndex = 6, daysOffline = 99 },
        }
        local out = ModPresets.Match(p, members, ctx, 1)
        if #out ~= 1 or out[1].key ~= "A" then return false, "the safe list and the rank limits hold" end
        return true
    end)
end
