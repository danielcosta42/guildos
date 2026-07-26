----------------------------------------------------------------------
-- BRutus Guild Manager - Compatibility Layer
-- All WoW version-sensitive API calls go through here (Rule 4).
-- Never scatter C_* guards across feature modules.
----------------------------------------------------------------------

BRutus.Compat = {}
local Compat = BRutus.Compat

-- Register the addon message prefix (C_ChatInfo vs legacy RegisterAddonMessagePrefix)
function Compat.RegisterAddonPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    end
end

-- Request a guild roster update
function Compat.GuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-- Check if a quest has been flagged as completed
function Compat.IsQuestComplete(questId)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questId)
    end
    return false
end

-- Schedule a one-shot callback after `delay` seconds
function Compat.After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    end
end

-- Create a repeating ticker (returns a ticker object with :Cancel())
function Compat.NewTicker(interval, fn, iterations)
    if C_Timer and C_Timer.NewTicker then
        return C_Timer.NewTicker(interval, fn, iterations)
    end
    return nil
end

-- Create a one-shot timer (returns a timer object with :Cancel())
function Compat.NewTimer(delay, fn)
    if C_Timer and C_Timer.NewTimer then
        return C_Timer.NewTimer(delay, fn)
    end
    return nil
end

-- Send an addon message through ChatThrottleLib
function Compat.SendAddonMessage(prefix, text, channel, target, prio, queueName, callbackFn, callbackArg)
    if ChatThrottleLib then
        ChatThrottleLib:SendAddonMessage(
            prio or "BULK",
            prefix,
            text,
            channel,
            target,
            queueName,
            callbackFn,
            callbackArg
        )
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(prefix, text, channel, target)
    end
end

-- Send a /who query (C_FriendList on BCC/modern; legacy global fallback)
function Compat.SendWho(filter)
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(filter)
    elseif SendWho then
        SendWho(filter)
    end
end

-- Route /who results to the API (true) or the Social frame (false)
function Compat.SetWhoToUI(toApi)
    if C_FriendList and C_FriendList.SetWhoToUI then
        C_FriendList.SetWhoToUI(toApi and true or false)
    elseif SetWhoToUI then
        SetWhoToUI(toApi and 1 or 0)
    end
end

-- Best map ID for a unit (C_Map on BCC/modern). Returns nil when the API is
-- unavailable or the unit has no map (e.g. mid-loading-screen).
function Compat.GetBestMapForUnit(unit)
    if C_Map and C_Map.GetBestMapForUnit then
        return C_Map.GetBestMapForUnit(unit)
    end
    return nil
end

-- Normalized position of a unit on `mapID` as x,y in 0..1. Returns nil inside
-- instances (C_Map returns no position there) or when the API is unavailable.
-- Handles both the Vector2DMixin return (has :GetXY()) and an older plain
-- {x=,y=} table, so a missing API degrades to zone-only rather than erroring.
function Compat.GetPlayerMapPosition(mapID, unit)
    if mapID and C_Map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(mapID, unit)
        if pos then
            if pos.GetXY then return pos:GetXY() end
            if pos.x and pos.y then return pos.x, pos.y end
        end
    end
    return nil
end

-- Whether this client may edit guild public notes
function Compat.CanEditPublicNote()
    if CanEditPublicNote then return CanEditPublicNote() and true or false end
    return false
end

-- Resolve a guild roster index for `name`, which may be "Name" or "Name-Realm";
-- `realm` (from a chat event, say) overrides any suffix on `name`.
--
-- A connected-realm guild can hold both Bob-RealmA and Bob-RealmB. Matching on
-- the short name alone and taking the FIRST hit writes to whichever Bob sorts
-- earlier, so: an exact Name-Realm match wins outright, a short-name match is
-- accepted only when it is unique, and anything ambiguous returns nil rather
-- than guessing.
function Compat.FindGuildRosterIndex(name, realm)
    if not name or name == "" then return nil end
    local short = name:match("^([^-]+)") or name
    realm = realm or name:match("^[^-]+%-(.+)$")
    local n = GetNumGuildMembers() or 0
    local onlyIdx, hits = nil, 0
    for i = 1, n do
        local full = GetGuildRosterInfo(i)
        if full then
            local fs = full:match("^([^-]+)") or full
            local fr = full:match("^[^-]+%-(.+)$")
            if fs == short then
                if realm and realm ~= "" and fr == realm then
                    return i                    -- exact Name-Realm
                end
                hits = hits + 1
                onlyIdx = i
            end
        end
    end
    if hits == 1 then return onlyIdx end
    return nil                                  -- absent, or ambiguous
end

-- Current public note for a guild member, or nil when they cannot be resolved.
function Compat.GetGuildPublicNote(name, realm)
    local idx = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return nil end
    local _, _, _, _, _, _, note = GetGuildRosterInfo(idx)
    return note or ""
end

-- Set a guild member's public note by name (finds the roster index).
-- Returns true if applied. No-op (false) if the API/permission is absent, or
-- if the name cannot be resolved to exactly one roster row.
function Compat.SetGuildPublicNote(name, text, realm)
    if not name or not GuildRosterSetPublicNote or not (CanEditPublicNote and CanEditPublicNote()) then
        return false
    end
    local idx = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return false end
    -- Member-authored text: strip UI escapes and cap without splitting a
    -- codepoint (shared helper, Core/Utils.lua).
    GuildRosterSetPublicNote(idx, BRutus:SanitizeUserText(text, 31))
    return true
end
