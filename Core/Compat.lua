----------------------------------------------------------------------
-- BRutus Guild Manager - Compatibility Layer
-- All WoW version-sensitive API calls go through here (Rule 4).
-- Never scatter C_* guards across feature modules.
----------------------------------------------------------------------

BRutus.Compat = {}
local Compat = BRutus.Compat

----------------------------------------------------------------------
-- Which client this is and what it can do (ADR-0014). Read once, before any
-- module file loads, so a file can decide whether its content exists here.
-- WoW: Forever has no WOW_PROJECT_ID of its own yet: TBC Anniversary is
-- recognised by its project id and its interface together, and every other
-- client, an unknown one included, is "not Anniversary".
----------------------------------------------------------------------
local version, build, buildDate, interface = GetBuildInfo()
interface = tonumber(interface) or 0
local TBC_PROJECT = WOW_PROJECT_BURNING_CRUSADE_CLASSIC  -- nil on a client without the constant
BRutus.Client = {
    version = version,
    build = build,
    date = buildDate,
    interface = interface,
    projectId = WOW_PROJECT_ID,  -- diagnostics only; never branch on it
    isAnniversary = TBC_PROJECT ~= nil and WOW_PROJECT_ID == TBC_PROJECT
        and interface >= 20500 and interface < 30000,
    has = {
        secrets = issecretvalue ~= nil,
        chatLockdown = (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) ~= nil,
        tradeSkillUI = C_TradeSkillUI ~= nil,
        tooltipData = TooltipDataProcessor ~= nil,
        guildSetNote = (C_GuildInfo and C_GuildInfo.SetNote) ~= nil,
    },
}

-- Secret Values (WoW: Forever runs the retail system): a chat payload in messaging lockdown, or a
-- unit whose identity is restricted, arrives as a value addon code may pass along but not read.
-- Matching, comparing, concatenating or indexing with one raises, so a reader asks first.
-- True when any argument is secret; always false on a client without the system.
function Compat.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

-- A group unit's name, realm and class file, or nothing when the client keeps who it is secret.
function Compat.UnitIdentity(unit)
    local name, realm = UnitName(unit)
    local _, classFile = UnitClass(unit)
    if Compat.IsSecret(name, realm, classFile) then return end
    return name, realm, classFile
end

-- Register the addon message prefix (C_ChatInfo, else the legacy global)
function Compat.RegisterAddonPrefix(prefix)
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        return C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    end
    if RegisterAddonMessagePrefix then return RegisterAddonMessagePrefix(prefix) end
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
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questId)
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

-- Localized display name for a mapID (C_Map.GetMapInfo). Returns nil when the
-- API or the map is unknown, so callers substitute their own fallback.
function Compat.GetMapName(mapID)
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info then return info.name end
    end
    return nil
end

----------------------------------------------------------------------
-- World map frame access
--
-- The world map is a MapCanvasMixin frame. We only ever READ its state and
-- parent OUR OWN pins to its canvas; we never overwrite a Blizzard global.
-- All of it is guarded so a missing/renamed API degrades to a no-op instead
-- of erroring (Rule 4).
----------------------------------------------------------------------

-- The global WorldMapFrame, or nil if the world map addon is not loaded yet.
function Compat.GetWorldMapFrame()
    return WorldMapFrame
end

-- The world map canvas (the child the map art + pins live on). nil when the
-- map is not available. Handles the GetCanvas() accessor and the raw
-- ScrollContainer.Child fallback.
function Compat.GetWorldMapCanvas()
    local wmf = WorldMapFrame
    if not wmf then return nil end
    if wmf.GetCanvas then return wmf:GetCanvas() end
    local sc = wmf.ScrollContainer
    if sc and sc.Child then return sc.Child end
    return nil
end

-- The mapID currently displayed by the world map, or nil.
function Compat.GetShownMapID()
    local wmf = WorldMapFrame
    if wmf and wmf.GetMapID then return wmf:GetMapID() end
    return nil
end

-- Navigate the world map to a mapID (insecure, not a protected call).
function Compat.SetShownMapID(mapID)
    local wmf = WorldMapFrame
    if wmf and wmf.SetMapID and mapID then wmf:SetMapID(mapID) end
end

-- Ensure the world map is open. Skipped in combat (opening a UI panel is
-- restricted there). ToggleWorldMap loads the map addon on demand if needed.
-- Returns true when the map is (or was already) shown.
function Compat.OpenWorldMap()
    if InCombatLockdown and InCombatLockdown() then return false end
    local wmf = WorldMapFrame
    if wmf and wmf:IsShown() then return true end
    if ToggleWorldMap then
        ToggleWorldMap()
        return true
    end
    if wmf and ShowUIPanel then
        ShowUIPanel(wmf)
        return true
    end
    return false
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
    if not name or name == "" then return nil, "absent" end
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
    return nil, hits == 0 and "absent" or "ambiguous"
end

-- Current public note for a guild member, or nil and why ("absent", "ambiguous").
function Compat.GetGuildPublicNote(name, realm)
    local idx, why = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return nil, why end
    local _, _, _, _, _, _, note = GetGuildRosterInfo(idx)
    return note or ""
end

-- Set a guild member's public note by name. Returns true when written, or false
-- and why: "no-permission", "absent", "ambiguous", "no-guid" or "no-api".
-- 2.5.6 documents C_GuildInfo.SetNote(guid, note, isPublic) and not the old
-- GuildRosterSetPublicNote(index, note), which stays as the fallback (issue #5).
function Compat.SetGuildPublicNote(name, text, realm)
    if not (CanEditPublicNote and CanEditPublicNote()) then return false, "no-permission" end
    local idx, why = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return false, why end
    -- Member-authored text: strip UI escapes and cap without splitting a
    -- codepoint (shared helper, Core/Utils.lua).
    local note = BRutus:SanitizeUserText(text, 31)
    local guid = select(17, GetGuildRosterInfo(idx))
    if C_GuildInfo and C_GuildInfo.SetNote and guid then
        C_GuildInfo.SetNote(guid, note, true)
        return true
    end
    if GuildRosterSetPublicNote then
        GuildRosterSetPublicNote(idx, note)
        return true
    end
    return false, (C_GuildInfo and C_GuildInfo.SetNote) and "no-guid" or "no-api"
end

----------------------------------------------------------------------
-- Events and tooltip hooks a client may not have
----------------------------------------------------------------------

-- Register `event` on `frame`. RegisterEvent raises on an event name the
-- client does not know, and a new client (WoW: Forever) may lack TBC-era
-- ones such as CRAFT_SHOW. The miss is recorded for /guildos errors instead
-- of stopping the module that asked. Returns true when registered.
--
-- `expected` is for an event only some clients ever had: it still registers
-- where it exists, and where it does not it is a fact about the client rather
-- than a problem with the addon, so it stays out of the start-up list. The
-- probe reports it either way.
function Compat.RegisterEvent(frame, event, expected)
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then BRutus:RecordMissing("event " .. event, expected) end
    return ok
end

-- The Classic-era tooltip scripts and what the retail client calls the same
-- thing. Forever runs the retail tooltip: the frame has no OnTooltipSet*
-- script, and one call per data type covers every tooltip at once.
local TOOLTIP_TYPES = {
    OnTooltipSetItem = "Item",
    OnTooltipSetSpell = "Spell",
    OnTooltipSetUnit = "Unit",
}

-- What has already been handed to TooltipDataProcessor, by script and function,
-- and which tooltips each one is for: a caller asks for GameTooltip,
-- ItemRefTooltip and both shopping tooltips, and registering the same function
-- four times would add its lines four times.
local posted = {}

-- Hook `script` on a tooltip. Where the frame has it (Anniversary), that is a
-- HookScript. Where it does not but the client has the retail tooltip
-- (Forever), the same function is registered once through
-- TooltipDataProcessor, which calls it with the tooltip as its first argument,
-- the way the script did. That registration is for every tooltip of its type at
-- once, so what goes in is a wrapper that answers only for the tooltips this
-- caller asked for — otherwise a hook on GameTooltip alone would start writing
-- into every tooltip in the game, Blizzard's forbidden ones included, where a
-- line raises. A tooltip that is not built (nil) is skipped silently, and a
-- client with neither path is recorded for /guildos errors. Returns true when
-- this tooltip is covered.
function Compat.HookTooltip(tooltip, script, fn)
    if not tooltip then return false end
    if tooltip.HasScript and tooltip:HasScript(script) then
        tooltip:HookScript(script, fn)
        return true
    end
    local kind = TOOLTIP_TYPES[script]
    local dataType = kind and Enum and Enum.TooltipDataType and Enum.TooltipDataType[kind]
    if dataType and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        posted[script] = posted[script] or {}
        local wanted = posted[script][fn]
        if not wanted then
            wanted = {}
            posted[script][fn] = wanted
            TooltipDataProcessor.AddTooltipPostCall(dataType, function(tip, data)
                if not tip or not wanted[tip] then return end
                if tip.IsForbidden and tip:IsForbidden() then return end
                return fn(tip, data)
            end)
        end
        wanted[tooltip] = true
        return true
    end
    BRutus:RecordMissing("tooltip script " .. script)
    return false
end

-- What a tooltip is showing. `tooltip:GetItem()` and its siblings are the
-- Classic-era readers and the retail client answers through TooltipUtil, so
-- each asks the frame first — the same question HookTooltip asks to choose its
-- path, and on a client with both the reading then matches the hook — and falls
-- through when the frame has no answer. First two returns are the same on both:
-- name and link, name and spell id, name and unit. TooltipUtil adds a third
-- (the item id, the unit's guid); nothing reads it yet.
function Compat.TooltipItem(tooltip)
    if tooltip.GetItem then
        local name, link = tooltip:GetItem()
        if link then return name, link end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then return TooltipUtil.GetDisplayedItem(tooltip) end
end

function Compat.TooltipSpell(tooltip)
    if tooltip.GetSpell then
        local name, spellId = tooltip:GetSpell()
        if spellId then return name, spellId end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedSpell then return TooltipUtil.GetDisplayedSpell(tooltip) end
end

function Compat.TooltipUnit(tooltip)
    if tooltip.GetUnit then
        local name, unit = tooltip:GetUnit()
        if unit then return name, unit end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedUnit then return TooltipUtil.GetDisplayedUnit(tooltip) end
end

----------------------------------------------------------------------
-- Items, spells, auras and bags (issue #10)
-- Each prefers the namespaced API, falls back to the old global, and returns
-- nothing when the client has neither, so a caller degrades instead of raising.
----------------------------------------------------------------------

function Compat.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

-- C_Spell.GetSpellInfo returns a table; every caller reads the old global's order.
function Compat.GetSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spell)
        if not info then return nil end
        return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
    end
    if GetSpellInfo then return GetSpellInfo(spell) end
end

function Compat.GetSpellTexture(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    if GetSpellTexture then return GetSpellTexture(spell) end
end

-- In UnitBuff's order: name, icon, count, debuffType, duration, expirationTime,
-- source, isStealable, nameplateShowPersonal, spellId.
function Compat.UnitBuff(unit, index)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        local a = C_UnitAuras.GetBuffDataByIndex(unit, index)
        if not a then return nil end
        return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime,
            a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId
    end
    if UnitBuff then return UnitBuff(unit, index) end
end

function Compat.GetContainerNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
    if GetContainerNumSlots then return GetContainerNumSlots(bag) or 0 end
    return 0
end

function Compat.GetContainerItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
    if GetContainerItemLink then return GetContainerItemLink(bag, slot) end
end

-- The namespaced table ({ itemID, hyperlink, ... }), built from the old global's
-- returns when that is all the client has.
function Compat.GetContainerItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then return C_Container.GetContainerItemInfo(bag, slot) end
    if GetContainerItemInfo then
        local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
        if not link then return nil end
        return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality, isReadable = readable,
                 hasLoot = lootable, hyperlink = link, isFiltered = filtered, hasNoValue = noValue,
                 itemID = itemID or tonumber(link:match("item:(%d+)")) }
    end
end

function Compat.UseContainerItem(bag, slot)
    if C_Container and C_Container.UseContainerItem then return C_Container.UseContainerItem(bag, slot) end
    if UseContainerItem then return UseContainerItem(bag, slot) end
end

----------------------------------------------------------------------
-- Talents and skill lines (issue #10)
-- nil, "no-api" when the client has no such function, so own-character
-- collection leaves the field out instead of raising.
----------------------------------------------------------------------

function Compat.GetNumTalentTabs(isInspect)
    if not GetNumTalentTabs then return nil, "no-api" end
    if isInspect == nil then return GetNumTalentTabs() end
    return GetNumTalentTabs(isInspect)
end

function Compat.GetNumTalents(tab, isInspect)
    if not GetNumTalents then return nil, "no-api" end
    return GetNumTalents(tab, isInspect)
end

function Compat.GetTalentInfo(tab, index, isInspect)
    if not GetTalentInfo then return nil end
    return GetTalentInfo(tab, index, isInspect)
end

function Compat.GetNumSkillLines()
    if not GetNumSkillLines then return nil, "no-api" end
    return GetNumSkillLines()
end

function Compat.GetSkillLineInfo(index)
    if not GetSkillLineInfo then return nil end
    return GetSkillLineInfo(index)
end

----------------------------------------------------------------------
-- Addon messages, with their result (issue #10)
--
-- Sync goes through ChatThrottleLib, which re-queues AddonMessageThrottle itself
-- and hands every other result to the callback; loot goes out at once, as it
-- always did, because its roll timer starts at send. Either way the result decides:
--   - a chat lockdown holds the message, and everything sent after it so the
--     order stays; the queue is flushed when combat ends, when the zone changes,
--     and by a 2-second poll while anything waits, since a restriction can lift
--     with neither event;
--   - a channel throttle, and an addon-message throttle on a message sent now,
--     is retried after 1, 2, 4 and 8 seconds;
--   - anything else, or a message the client would refuse outright, is recorded
--     once per reason for /guildos errors and dropped: never silent, never
--     retried forever.
----------------------------------------------------------------------
local RESULT = (Enum and Enum.SendAddonMessageResult) or {}
local SUCCESS = RESULT.Success or 0
local CHANNEL_THROTTLE = RESULT.ChannelThrottle or 8
local ADDON_THROTTLE = RESULT.AddonMessageThrottle or 3
local LOCKDOWN = RESULT.AddOnMessageLockdown or RESULT.AddonMessageLockdown or 11
local RETRY_DELAYS = { 1, 2, 4, 8 }
local PRIORITIES = { BULK = true, NORMAL = true, ALERT = true }
Compat.HELD_MAX, Compat.HELD_POLL = 200, 2
Compat._held, Compat._reported = {}, {}

local function inLockdown()
    return (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) and true or false
end

local function record(msg, reason)
    reason = tostring(reason)
    if Compat._reported[reason] then return end
    Compat._reported[reason] = true
    BRutus:RecordError(string.format("Addon message on %s was not sent (result %s)", tostring(msg.channel), reason))
end

local polling = false
local function poll()
    polling = false
    Compat.FlushHeldMessages()
end

local function hold(msg)
    local held = Compat._held
    -- ponytail: past the cap the oldest message goes; sync re-broadcasts anyway.
    if #held >= Compat.HELD_MAX then table.remove(held, 1) end
    held[#held + 1] = msg
    if not polling then
        polling = true
        Compat.After(Compat.HELD_POLL, poll)
    end
end

local send

local function onResult(msg, didSend, result)
    if didSend or result == SUCCESS then return end
    if result == LOCKDOWN then return hold(msg) end
    -- ChatThrottleLib re-queues AddonMessageThrottle on its own path; a message sent now retries it here.
    local throttled = result == CHANNEL_THROTTLE or (msg.now and result == ADDON_THROTTLE)
    if throttled and msg.tries <= #RETRY_DELAYS then
        local delay = RETRY_DELAYS[msg.tries]
        msg.tries = msg.tries + 1
        return Compat.After(delay, function() send(msg) end)
    end
    record(msg, result)
end

send = function(msg)
    if inLockdown() or #Compat._held > 0 then return hold(msg) end
    if ChatThrottleLib and not msg.now then
        ChatThrottleLib:SendAddonMessage(msg.prio, msg.prefix, msg.text, msg.channel, msg.target, msg.queue,
            function(_, didSend, result) onResult(msg, didSend, result) end)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        local r = C_ChatInfo.SendAddonMessage(msg.prefix, msg.text, msg.channel, msg.target)
        onResult(msg, r == nil or r == true or r == SUCCESS, r)
    else
        record(msg, "no-api")
    end
end

-- What ChatThrottleLib or the client would refuse outright is recorded, never queued.
local function queue(msg)
    -- C_ChatInfo.SendAddonMessage refuses secret arguments outright (SecretArguments = NotAllowed).
    if Compat.IsSecret(msg.prefix, msg.text, msg.channel, msg.target) then
        return record(msg, "secret")
    end
    if type(msg.prefix) ~= "string" or msg.prefix == "" or #msg.prefix > 16 or type(msg.text) ~= "string"
        or #msg.text > 255 or type(msg.channel) ~= "string" or not PRIORITIES[msg.prio] then
        return record(msg, "invalid")
    end
    send(msg)
end

-- Send an addon message through ChatThrottleLib; prio is its "BULK" (default), "NORMAL" or "ALERT".
function Compat.SendAddonMessage(prefix, text, channel, target, prio, queueName)
    queue({ prefix = prefix, text = text, channel = channel, target = target,
            prio = prio or "BULK", queue = queueName, tries = 1 })
end

-- Send an addon message now, past ChatThrottleLib's queue, with the same results: loot, whose timers start at send.
function Compat.SendAddonMessageNow(prefix, text, channel, target)
    queue({ prefix = prefix, text = text, channel = channel, target = target, prio = "ALERT", now = true, tries = 1 })
end

-- Sends what a lockdown held, in order, one at a time: a message that raises is recorded and the
-- rest still go. While the lockdown lasts, send() holds each one again.
function Compat.FlushHeldMessages()
    local pending = Compat._held
    Compat._held = {}
    for _, msg in ipairs(pending) do
        local ok = pcall(send, msg)
        if not ok then record(msg, "error") end
    end
end

local flusher = CreateFrame("Frame")
Compat.RegisterEvent(flusher, "PLAYER_REGEN_ENABLED")
Compat.RegisterEvent(flusher, "ZONE_CHANGED_NEW_AREA")
flusher:SetScript("OnEvent", function() Compat.FlushHeldMessages() end)
