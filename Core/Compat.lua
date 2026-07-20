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
