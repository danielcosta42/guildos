----------------------------------------------------------------------
-- Guild OS - Compatibility Layer
-- All WoW version-sensitive API calls go through here (Rule 4).
-- Never scatter C_* guards across feature modules.
----------------------------------------------------------------------

GuildOS.Compat = {}
local Compat = GuildOS.Compat

----------------------------------------------------------------------
-- Which client this is and what it can do (ADR-0014, ADR-0026). Read once, before
-- any module file loads, so a file can decide whether its content exists here.
-- WoW: Forever has no WOW_PROJECT_ID of its own yet: TBC Anniversary and retail
-- are each recognised by a project id and an interface together, and every other
-- client, an unknown one included, is WoW: Forever. Forever runs the mainline UI
-- and may answer the mainline id, but its interface is 16001.
----------------------------------------------------------------------
local version, build, buildDate, interface = GetBuildInfo()
interface = tonumber(interface) or 0
local TBC_PROJECT = WOW_PROJECT_BURNING_CRUSADE_CLASSIC  -- nil on a client without the constant
local isAnniversary = TBC_PROJECT ~= nil and WOW_PROJECT_ID == TBC_PROJECT
    and interface >= 20500 and interface < 30000
local isRetail = WOW_PROJECT_MAINLINE ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
    and interface >= 100000
-- The classes a character can be. Retail adds the four Classic never had, after the nine.
local CLASSIC_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local RETAIL_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    "DEATHKNIGHT", "DEMONHUNTER", "MONK", "EVOKER" }
GuildOS.Client = {
    version = version,
    build = build,
    date = buildDate,
    interface = interface,
    projectId = WOW_PROJECT_ID,  -- diagnostics only; never branch on it
    isAnniversary = isAnniversary,
    isRetail = isRetail,
    -- What the companion payload says; nothing else branches on it.
    game = isAnniversary and "ANNIVERSARY" or isRetail and "RETAIL" or "FOREVER",
    -- The game's level cap: TBC's 70, WoW: Forever's 60 (issue #53), Midnight's 90. The Forever
    -- beta caps lower for a while; the game is 60, and that is what "the top" means to a guild.
    maxLevel = isAnniversary and 70 or isRetail and 90 or 60,
    -- The raid sizes an event can have, and the one it starts at: TBC's 10 and 25, with 40 for
    -- the old raids; WoW: Forever's 10 and 20 a tier, with Onyxia at 40; retail's flex 10 to 30
    -- with mythic at 20. The default is each game's main raid (issues #89, #92, #165).
    raidSizes = isAnniversary and { 10, 25, 40 } or isRetail and { 10, 20, 30 } or { 10, 20, 40 },
    defaultRaidSize = isAnniversary and 25 or 20,
    classes = isRetail and RETAIL_CLASSES or CLASSIC_CLASSES,
    -- Where a missing enchant is a real problem: TBC's nine slots (Forever's too), Midnight's
    -- head, shoulder, chest, legs (spellthread, armor kit), feet, both rings and both weapons;
    -- cloak and wrist enchants are gone. An off hand counts only as a weapon (issue #177).
    enchantSlots = isRetail and { 1, 3, 5, 7, 8, 11, 12, 16, 17 } or { 1, 3, 5, 7, 8, 9, 10, 15, 16 },
    has = {
        secrets = issecretvalue ~= nil,
        chatLockdown = (C_ChatInfo and C_ChatInfo.InChatMessagingLockdown) ~= nil,
        tradeSkillUI = C_TradeSkillUI ~= nil,
        tooltipData = TooltipDataProcessor ~= nil,
        guildSetNote = (C_GuildInfo and C_GuildInfo.SetNote) ~= nil,
        -- Never on Anniversary or retail, where UnitFullName's second slot is the realm (issue #26).
        surnames = not isAnniversary and not isRetail
            and (C_PlayerInfo and C_PlayerInfo.ShouldDisplaySurname) ~= nil,
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
-- The token itself can be secret (a restricted unit's tooltip), and UnitClass refuses one in
-- addon code rather than answer secret, so it is asked first (issue #116).
function Compat.UnitIdentity(unit)
    if Compat.IsSecret(unit) then return end
    local name, realm = UnitName(unit)
    local _, classFile = UnitClass(unit)
    if Compat.IsSecret(name, realm, classFile) then return end
    return name, realm, classFile
end

-- Whether a boss fight is going on. The global is a deprecation fallback on all three clients, kept by a
-- CVar and bound for removal; the addon asks the namespace first and takes no for an answer without either.
function Compat.IsEncounterInProgress()
    local ask = C_InstanceEncounter and C_InstanceEncounter.IsEncounterInProgress or IsEncounterInProgress
    return ask ~= nil and ask() == true
end

-- The region this client plays in, as guildos.me writes it, from GetCurrentRegion(): 1 the Americas
-- ("us"), 2 Korea, 3 Europe, 4 Taiwan. Nil for any other answer (China, a test client), which the site
-- has no world for, with the number the client gave (issue #182).
local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw" }
function Compat.Region()
    local id = GetCurrentRegion and GetCurrentRegion()
    if Compat.IsSecret(id) then return nil end
    return REGIONS[id], id
end

-- The realms a character here can be invited from: its own and the ones connected to it (retail's
-- GetAutoCompleteRealms; Forever has no realms and answers nothing). A guild on any other realm
-- cannot invite this character, so the guild finder leaves it out (specs/071). Names as the client
-- writes them, never nil.
function Compat.ConnectedRealms()
    local out = {}
    local own = GetRealmName and GetRealmName()
    if type(own) == "string" and own ~= "" and not Compat.IsSecret(own) then out[1] = own end
    local linked = GetAutoCompleteRealms and GetAutoCompleteRealms()
    if type(linked) == "table" then
        for _, name in ipairs(linked) do
            if type(name) == "string" and name ~= "" and not Compat.IsSecret(name) then out[#out + 1] = name end
        end
    end
    return out
end

-- The guild's tabard as the game draws it (issue #213; read in game on retail 2026-10-29, Forever's API is
-- the same): GetGuildLogoInfo's three colours as bytes and the emblem's style, and GetGuildTabardFiles'
-- six files, whose last two are the border (its style is only in them). Nil with no guild, no tabard,
-- no such call or anything secret: the site turns this into its own code (specs/060).
function Compat.GuildTabard()
    if not (GetGuildLogoInfo and GetGuildTabardFiles) then return nil end
    local logo = { GetGuildLogoInfo() }
    local files = { GetGuildTabardFiles() }
    if #logo < 11 or #files < 6 then return nil end
    for i = 1, 11 do
        if i ~= 10 and (Compat.IsSecret(logo[i]) or type(logo[i]) ~= "number") then return nil end
    end
    for i = 1, 6 do
        if Compat.IsSecret(files[i]) or type(files[i]) ~= "number" or files[i] <= 0 then return nil end
    end
    local byte = function(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
    return {
        emblemStyle = logo[11],
        background = { byte(logo[1]), byte(logo[2]), byte(logo[3]) },
        border = { byte(logo[4]), byte(logo[5]), byte(logo[6]) },
        emblem = { byte(logo[7]), byte(logo[8]), byte(logo[9]) },
        files = { files[1], files[2], files[3], files[4], files[5], files[6] },
    }
end

-- The client's own count of the seconds to its region's weekly reset; nil where the client has no
-- such call. Only RaidTracker's self-test reads it, against the reset table (guildos-web#199).
function Compat.SecondsUntilWeeklyReset()
    local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if Compat.IsSecret(left) then return nil end
    return tonumber(left)
end

-- My own name the way the guild roster and every addon-message sender write it. WoW: Forever
-- 1.60.1.70009 cut UnitName("player") to the first name ("Chehul") while the roster says
-- "Chehul Druida"; there UnitFullName("player") returns the first name and the surname apart,
-- where every other client returns the realm in that slot (issue #26).
function Compat.PlayerName()
    if GuildOS.Client.has.surnames then
        local first, surname = UnitFullName("player")
        if not Compat.IsSecret(first, surname) and first and surname and surname ~= "" then
            return first .. " " .. surname
        end
    end
    return (UnitName("player"))
end

-- Whether a group unit is me, by identity rather than by name: on WoW: Forever the name shapes
-- disagree (UnitName gives the first name, the roster and chat the whole name; issue #26).
-- A comparison the client keeps secret counts as not me.
function Compat.IsPlayer(unit)
    local same = UnitIsUnit(unit, "player")
    if Compat.IsSecret(same) then return false end
    return same and true or false
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

--- The game's own meter of an addon's CPU (C_AddOnProfiler, retail 11.0.2 on), in ms a frame:
--- { recent, session, peak, all } (`all` is every addon together), or nil where the client has none
--- or answers with nothing (issue #324). Each value may be nil on its own.
function Compat.AddOnCPU(addon)
    local P = C_AddOnProfiler
    local M = Enum and Enum.AddOnProfilerMetric
    if type(P) ~= "table" or type(M) ~= "table" or type(P.GetAddOnMetric) ~= "function" then return nil end
    -- A metric this client lacks reaches the API as nil, which raises: pcall makes that a nil too.
    local function read(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, v = pcall(fn, ...)
        return ok and tonumber(v) or nil
    end
    local out = {
        recent  = read(P.GetAddOnMetric, addon, M.RecentAverageTime),
        session = read(P.GetAddOnMetric, addon, M.SessionAverageTime),
        peak    = read(P.GetAddOnMetric, addon, M.PeakTime),
        all     = read(P.GetOverallMetric, M.RecentAverageTime),
    }
    if not (out.recent or out.session) then return nil end
    return out
end

-- Send a /who query (C_FriendList on BCC/modern; legacy global fallback)
function Compat.SendWho(filter)
    if C_FriendList and C_FriendList.SendWho then
        C_FriendList.SendWho(filter)
    elseif SendWho then
        SendWho(filter)
    end
end

-- Route /who results to the API (true) or the Social frame (false). The function is
-- C_FriendList.SetWhoToUi, lower-case i, on every client: the old spelling found nothing on
-- either client, so a /who started here never reached WHO_LIST_UPDATE (issue #71). The other
-- two stay as a fallback. Blizzard's own Who list turns the flag on while it is open; giving it
-- back (false) while that list is up would stop the list refreshing, so then it stays on.
function Compat.SetWhoToUI(toApi)
    if not toApi and ((WhoFrame and WhoFrame:IsVisible()) or (LFGWhoListFrame and LFGWhoListFrame:IsVisible())) then
        toApi = true
    end
    if C_FriendList and C_FriendList.SetWhoToUi then
        C_FriendList.SetWhoToUi(toApi and true or false)
    elseif C_FriendList and C_FriendList.SetWhoToUI then
        C_FriendList.SetWhoToUI(toApi and true or false)
    elseif SetWhoToUI then
        SetWhoToUI(toApi and 1 or 0)
    end
end

-- The /who filter for one exact character, built the way each client's own UI builds it
-- (ItemRefHandlers.lua): WHO_TAG_EXACT ("x-") plus the name, and on WoW: Forever the name with
-- its surname separator swapped for the link one, which a name with a surname needs. A client
-- with neither gets the n-"Name" filter (issue #71).
function Compat.WhoExact(name)
    if WHO_TAG_EXACT and C_NameUtil and C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator then
        return WHO_TAG_EXACT .. C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(name)
    elseif WHO_TAG_EXACT then
        return WHO_TAG_EXACT .. name
    end
    return 'n-"' .. name .. '"'
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
-- Whether Guild OS may write a member's public note. Only TBC Anniversary lets an addon: WoW: Forever
-- 1.60.1.70790 forbids C_GuildInfo.SetNote to addons (ADDON_ACTION_FORBIDDEN on the roster's Add note,
-- 2026-11-05), as it forbids GuildInvite (#256), and retail runs the same API (#259).
function Compat.CanEditPublicNote()
    if not GuildOS.Client.isAnniversary then return false end
    if CanEditPublicNote then return CanEditPublicNote() and true or false end
    return false
end

-- Whether this client may read guild officer notes. Without it the roster answers "" for every one.
function Compat.CanViewOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() and true or false end
    if CanViewOfficerNote then return CanViewOfficerNote() and true or false end
    return false
end

----------------------------------------------------------------------
-- Rank changes and removals (issue #420). The rank's own rights are the game's Can* calls, nil-guarded:
-- a client without one answers "no". GuildPromote, GuildDemote and GuildUninvite are protected: an
-- addon's call is ADDON_ACTION_FORBIDDEN, from a click too (ADR-0010). What the game lets through is
-- its own /gpromote, /gdemote and /gremove run by a secure action button the player clicks or a
-- /click macro presses: the game runs the line, the addon only wrote it (ADR-0038).
----------------------------------------------------------------------
function Compat.CanGuildPromote()
    return (CanGuildPromote and CanGuildPromote()) and true or false
end

function Compat.CanGuildDemote()
    return (CanGuildDemote and CanGuildDemote()) and true or false
end

function Compat.CanGuildRemove()
    return (CanGuildRemove and CanGuildRemove()) and true or false
end

-- This character's 0-based guild rank (0 = Guild Master), or nil outside a guild.
function Compat.MyGuildRankIndex()
    if not (IsInGuild and IsInGuild()) or not GetGuildInfo then return nil end
    local _, _, rankIndex = GetGuildInfo("player")
    return tonumber(rankIndex)
end

-- The game's own slash command for a rank change or a removal, in this client's spelling (the
-- SLASH_* strings the chat frame registers), with the English one where a client lacks it.
local RANK_SLASH = {
    promote = { "SLASH_GUILD_PROMOTE1", "/gpromote" },
    demote  = { "SLASH_GUILD_DEMOTE1", "/gdemote" },
    remove  = { "SLASH_GUILD_UNINVITE1", "/gremove" },
}

-- The line that does `action` ("promote", "demote", "remove") to `name`, or nil: an unknown action, or a name
-- with a character that could start or carry a second command (; / \ |) or a line break.
-- Retail names the member with the realm, as a guild there spans connected realms (#184); the other
-- clients' guilds are one realm, and the short name is the one their commands take. Where the game spells
-- a surname with a space (WoW: Forever, "Chehul Druida"), the name goes as /w takes it, the hyphen for the
-- space (GuildOS:WhisperTarget): a space would end the name there. Unverified for /gpromote (specs/bulk-actions).
function Compat.GuildRankCommand(action, name)
    local slash = RANK_SLASH[action]
    if not slash or type(name) ~= "string" or name == "" or name:find("[;/\\|\r\n]") then return nil end
    if not GuildOS.Client.isRetail then name = name:match("^([^-]+)") or name end
    name = GuildOS:WhisperTarget(strtrim and strtrim(name) or name)
    if name == "" or name:find("%s") then return nil end
    local cmd = _G[slash[1]]
    if type(cmd) ~= "string" or not cmd:match("^/%S+$") then cmd = slash[2] end
    return cmd .. " " .. name
end

-- Whether a secure button may run that line. WoW: Forever refused a /ginvite written by the addon on a
-- secure button (MACRO_ACTION_BLOCKED, 1.60.1.70790, #256): there the officer types the line instead.
function Compat.SecureGuildMacro()
    return GuildOS.Client.game ~= "FOREVER"
end

-- The game's "cast on key down" option (ActionButtonUseKeyDown): true or false, or nil on a client without it.
local function keyDownOption()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, "ActionButtonUseKeyDown")
    if not ok or v == nil then return nil end
    return tostring(v) == "1"
end

-- Register a secure action button for its clicks. A client with the key-down option (retail, and the newer
-- Classic templates) may act on the press or on the release by it, a /click included: the button listens to
-- both, and SecureClickActs lets exactly one of them arm the line, so a click acts once whichever the template
-- runs. A client without the option acts on the release.
function Compat.SecureClicks(button)
    if keyDownOption() ~= nil then
        button:RegisterForClicks("AnyUp", "AnyDown")
    else
        button:RegisterForClicks("AnyUp")
    end
end

-- Whether the click event with this `down` is the one that arms the line (see SecureClicks).
function Compat.SecureClickActs(down)
    local opt = keyDownOption()
    if opt == nil then return not down end
    return (down and true or false) == opt
end

-- The macro line that presses button `name` the way SecureClickActs acts on: with the key-down option on,
-- /click must say it is a press ("LeftButton 1"), or it arrives as a release and does nothing.
function Compat.ClickMacro(name)
    if keyDownOption() then return "/click " .. name .. " LeftButton 1" end
    return "/click " .. name
end

-- Set the line a secure action button runs. Out of combat only: the game refuses SetAttribute on a
-- protected frame in combat. Returns whether it was set.
function Compat.SetSecureMacro(button, text)
    if Compat.InCombat() then return false end
    button:SetAttribute("type", "macro")
    button:SetAttribute("macrotext", text or "")
    return true
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
    -- Retail's roster spells realms normalized; "Tol Barad" from GetRealmName() is its "TolBarad" (ADR-0026).
    if realm and GuildOS.Client.isRetail then realm = realm:gsub("[%s%-]", "") end
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
    if not Compat.CanEditPublicNote() then return false, "no-permission" end
    local idx, why = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return false, why end
    -- Member-authored text: strip UI escapes and cap without splitting a
    -- codepoint (shared helper, Core/Utils.lua).
    local note = GuildOS:SanitizeUserText(text, 31)
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

-- Whether Guild OS may write a member's officer note (issue #429): as for the public note, only TBC
-- Anniversary lets an addon; WoW: Forever and retail forbid C_GuildInfo.SetNote to addons.
function Compat.CanEditOfficerNote()
    if not GuildOS.Client.isAnniversary then return false end
    if CanEditOfficerNote then return CanEditOfficerNote() and true or false end
    return false
end

-- Whether this character's rank may edit that note in the game's own roster ("public" or "officer"),
-- whether or not an addon may write it: where the addon may not, the player types it there (#429).
function Compat.RankEditsNote(which)
    if which == "officer" then
        if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then return C_GuildInfo.CanEditOfficerNote() and true or false end
        return (CanEditOfficerNote and CanEditOfficerNote()) and true or false
    end
    if C_GuildInfo and C_GuildInfo.CanEditPublicNote then return C_GuildInfo.CanEditPublicNote() and true or false end
    return (CanEditPublicNote and CanEditPublicNote()) and true or false
end

-- Whether Guild OS may write that note ("public" or "officer") on this client.
function Compat.CanWriteNote(which)
    if which == "officer" then return Compat.CanEditOfficerNote() end
    return Compat.CanEditPublicNote()
end

-- A guild member's officer note, or nil and why ("absent", "ambiguous", "hidden": this rank cannot read them).
function Compat.GetGuildOfficerNote(name, realm)
    if not Compat.CanViewOfficerNote() then return nil, "hidden" end
    local idx, why = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return nil, why end
    local _, _, _, _, _, _, _, onote = GetGuildRosterInfo(idx)
    return onote or ""
end

-- Set a guild member's officer note by name, as SetGuildPublicNote does the public one (issue #429).
function Compat.SetGuildOfficerNote(name, text, realm)
    if not Compat.CanEditOfficerNote() then return false, "no-permission" end
    local idx, why = Compat.FindGuildRosterIndex(name, realm)
    if not idx then return false, why end
    local note = GuildOS:SanitizeUserText(text, 31)
    local guid = select(17, GetGuildRosterInfo(idx))
    if C_GuildInfo and C_GuildInfo.SetNote and guid then
        C_GuildInfo.SetNote(guid, note, false)
        return true
    end
    if GuildRosterSetOfficerNote then
        GuildRosterSetOfficerNote(idx, note)
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
    if not ok then GuildOS:RecordMissing("event " .. event, expected) end
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
    GuildOS:RecordMissing("tooltip script " .. script)
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
-- The guild bank (issue #380)
-- The item and log calls are the same legacy globals on TBC Anniversary, WoW: Forever and retail
-- (Blizzard's own guild bank UI calls them alike on all three); only C_GuildBank, its switch, is
-- namespaced. Each answers nothing on a client without the function, so the feature hides instead
-- of raising. The 98 slots and the 14 per column are file-local in Blizzard's UI, not globals.
----------------------------------------------------------------------
Compat.GUILD_BANK_SLOTS = 98      -- MAX_GUILDBANK_SLOTS_PER_TAB on every client
Compat.GUILD_BANK_PER_COLUMN = 14 -- NUM_SLOTS_PER_GUILDBANK_GROUP: 7 columns of 14 (two sub-columns of 7)
Compat.GUILD_BANKER_INTERACTION = 10  -- Enum.PlayerInteractionType.GuildBanker, where the enum is missing

-- Whether this client has a guild bank at all. WoW: Forever ships the bank's UI with the retail files,
-- but whether its servers open one is the server's call: C_GuildBank.IsGuildBankEnabled answers it on
-- all three clients. A client without the function and with the old globals (an older Classic) has one.
function Compat.HasGuildBank()
    if not (GetNumGuildBankTabs and GetGuildBankItemInfo and QueryGuildBankTab) then return false end
    if C_GuildBank and C_GuildBank.IsGuildBankEnabled then
        local ok, on = pcall(C_GuildBank.IsGuildBankEnabled)
        if ok and on ~= nil then return on and true or false end
    end
    return true
end

-- The most tabs a guild may buy: 6 on TBC Anniversary, 8 on retail and Forever.
function Compat.GuildBankMaxTabs()
    return tonumber(MAX_GUILDBANK_TABS) or (GuildOS.Client.isAnniversary and 6 or 8)
end

function Compat.GuildBankTabCount()
    return GetNumGuildBankTabs and tonumber(GetNumGuildBankTabs()) or 0
end

-- name, icon, isViewable, canDeposit, numWithdrawals, remainingWithdrawals. -1 withdrawals: no limit.
function Compat.GuildBankTabInfo(tab)
    if not GetGuildBankTabInfo then return nil end
    return GetGuildBankTabInfo(tab)
end

-- texture, count, locked, link for one slot; nil texture when the slot is empty.
function Compat.GuildBankSlot(tab, slot)
    if not GetGuildBankItemInfo then return nil end
    local texture, count, locked = GetGuildBankItemInfo(tab, slot)
    if not texture then return nil end
    return texture, tonumber(count) or 1, locked and true or false, GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
end

function Compat.QueryGuildBankTab(tab)
    if QueryGuildBankTab then QueryGuildBankTab(tab) end
end

-- The log of `tab`, or the money log for tab MAX_GUILDBANK_TABS + 1.
function Compat.QueryGuildBankLog(tab)
    if QueryGuildBankLog then QueryGuildBankLog(tab) end
end

function Compat.GuildBankMoney()
    return GetGuildBankMoney and tonumber(GetGuildBankMoney()) or nil
end

-- The item log of a tab, oldest first (the game's index 1 is the oldest):
-- { type, name, link, count, tab1, tab2, ago } with `ago` in hours.
function Compat.GuildBankItemLog(tab)
    local out = {}
    if not (GetNumGuildBankTransactions and GetGuildBankTransaction) then return out end
    for i = 1, tonumber(GetNumGuildBankTransactions(tab)) or 0 do
        local kind, name, link, count, tab1, tab2, y, mo, d, h = GetGuildBankTransaction(tab, i)
        if kind then
            out[#out + 1] = { type = kind, name = name, link = link, count = tonumber(count) or 1,
                tab1 = tonumber(tab1), tab2 = tonumber(tab2),
                ago = (((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24) + (tonumber(h) or 0) }
        end
    end
    return out
end

-- The money log, oldest first: { type, name, amount, ago } with `amount` in copper and `ago` in hours.
function Compat.GuildBankMoneyLog()
    local out = {}
    if not (GetNumGuildBankMoneyTransactions and GetGuildBankMoneyTransaction) then return out end
    for i = 1, tonumber(GetNumGuildBankMoneyTransactions()) or 0 do
        local kind, name, amount, y, mo, d, h = GetGuildBankMoneyTransaction(i)
        if kind then
            out[#out + 1] = { type = kind, name = name, amount = tonumber(amount) or 0,
                ago = (((tonumber(y) or 0) * 365 + (tonumber(mo) or 0) * 30 + (tonumber(d) or 0)) * 24) + (tonumber(h) or 0) }
        end
    end
    return out
end

-- Picking up and splitting need no hardware event (sorters drive them from timers on every client);
-- they act on the tab the bank is showing, so the caller selects it first.
function Compat.GuildBankPickup(tab, slot)
    if PickupGuildBankItem then PickupGuildBankItem(tab, slot) end
end

function Compat.GuildBankSplit(tab, slot, count)
    if SplitGuildBankItem then SplitGuildBankItem(tab, slot, count) end
end

function Compat.GuildBankCurrentTab()
    return GetCurrentGuildBankTab and tonumber(GetCurrentGuildBankTab()) or nil
end

function Compat.SetGuildBankCurrentTab(tab)
    if SetCurrentGuildBankTab then SetCurrentGuildBankTab(tab) end
end

function Compat.IsGuildLeader()
    return IsGuildLeader and IsGuildLeader() and true or false
end

-- Whether the cursor holds anything, and empties it: a move left on the cursor is dropped back.
-- CursorHasItem misses a guild bank item on some clients; GetCursorInfo names it ("guildbankitem").
function Compat.CursorHasItem()
    if CursorHasItem and CursorHasItem() then return true end
    return (GetCursorInfo and GetCursorInfo() ~= nil) and true or false
end

-- What the cursor holds, as GetCursorInfo says it: its type ("item", "guildbankitem", ...) and id.
function Compat.CursorInfo()
    if not GetCursorInfo then return nil end
    local ok, kind, id = pcall(GetCursorInfo)
    if ok then return kind, id end
end

function Compat.ClearCursor()
    if ClearCursor then ClearCursor() end
end

function Compat.InCombat()
    return (InCombatLockdown and InCombatLockdown()) and true or false
end

-- Whether a PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE is the guild banker's.
function Compat.IsGuildBankerInteraction(kind)
    local want = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
    return tonumber(kind) == (want or Compat.GUILD_BANKER_INTERACTION)
end

-- The events that say the bank opened and closed. Retail and Forever say it through the interaction
-- manager; TBC Anniversary still sends GUILDBANKFRAME_OPENED/CLOSED as well. Both are registered and
-- the module drops the second of a pair.
function Compat.RegisterGuildBankEvents(frame)
    for _, ev in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
            "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANKLOG_UPDATE",
            "GUILDBANK_UPDATE_MONEY", "GUILDBANK_UPDATE_TABS", "GUILDBANK_ITEM_LOCK_CHANGED",
            "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_DISABLED" }) do
        Compat.RegisterEvent(frame, ev, true)
    end
end

-- Taking an item out of the guild bank into the bags (it counts as a withdrawal).
function Compat.GuildBankAutoStore(tab, slot)
    if AutoStoreGuildBankItem then AutoStoreGuildBankItem(tab, slot) end
end

-- Putting gold into the guild bank, and the player's own gold.
function Compat.DepositGuildBankMoney(copper)
    if DepositGuildBankMoney and tonumber(copper) and copper > 0 then DepositGuildBankMoney(copper) end
end

function Compat.PlayerMoney()
    return GetMoney and tonumber(GetMoney()) or 0
end

-- What a vendor pays for one, the level it asks for and its own item level, when the client has the
-- item cached.
function Compat.ItemValue(item)
    local name, _, _, itemLevel, reqLevel, _, _, _, _, _, sellPrice = Compat.GetItemInfo(item)
    if not name then return nil end
    return tonumber(sellPrice) or 0, tonumber(reqLevel) or 0, tonumber(itemLevel) or 0
end

-- What one sells for at the auction house, from an addon that knows (Auctionator, TSM), or nil.
-- Both are optional and called under pcall: their APIs are theirs to change.
function Compat.AuctionPrice(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
        local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "GuildOS", itemID)
        if ok and tonumber(price) and price > 0 then return price end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local ok, price = pcall(TSM_API.GetCustomPriceValue, "DBMarket", "i:" .. itemID)
        if ok and tonumber(price) and price > 0 then return price end
    end
    return nil
end

-- What an item is, from its id or link alone, with no item cache: id, icon, classID, subClassID.
function Compat.ItemInstant(item)
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (instant and item) then return nil end
    local id, _, _, _, icon, classID, subClassID = instant(item)
    return tonumber(id), icon, tonumber(classID), tonumber(subClassID)
end

-- The item's name, quality, item level and stack size, when the client has it cached; nil otherwise
-- (asking starts the load, and GET_ITEM_INFO_RECEIVED follows).
function Compat.ItemDetails(item)
    local name, _, quality, level, _, _, _, stack = Compat.GetItemInfo(item)
    if not name then return nil end
    return name, tonumber(quality), tonumber(level), tonumber(stack)
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

-- Whether an item is a weapon, from its id alone (no item cache needed); nil when the client
-- cannot say. A shield or an off-hand frill takes no enchant on retail (issue #177).
function Compat.IsWeapon(item)
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (instant and item) then return nil end
    local _, _, _, _, _, classID = instant(item)
    return classID == 2   -- Enum.ItemClass.Weapon
end

-- An item's level as it is worn. On retail (ADR-0026) upgrades, crafting and the track an item
-- dropped from move it away from GetItemInfo's base level, `base`, which every other client keeps.
function Compat.ItemLevel(link, base)
    if GuildOS.Client.isRetail and C_Item and C_Item.GetDetailedItemLevelInfo then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if tonumber(level) and level > 0 then return level end
    end
    return base
end

-- My equipped average as the game shows it, on retail; nil elsewhere, where the addon averages its
-- own slots as it always has.
function Compat.AverageItemLevel()
    if not (GuildOS.Client.isRetail and GetAverageItemLevel) then return nil end
    local _, equipped = GetAverageItemLevel()
    equipped = tonumber(equipped)
    if not equipped or equipped <= 0 then return nil end
    return math.floor(equipped)
end

-- An inspected unit's equipped average as the game computes it, on retail (issue #184): the item
-- level of a guildmate who has no Guild OS to send theirs. Needs INSPECT_READY first. Nil
-- elsewhere, before the inspect has the gear, or when the client keeps it secret.
function Compat.InspectItemLevel(unit)
    if not (GuildOS.Client.isRetail and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) then return nil end
    local level = C_PaperDollInfo.GetInspectItemLevel(unit)
    if Compat.IsSecret(level) then return nil end
    level = tonumber(level)
    if not level or level <= 0 then return nil end
    return math.floor(level)
end

-- The primary stat my spec plays on, as UnitStat numbers it (1 strength, 2 agility, 4 intellect),
-- on retail (issue #184); nil elsewhere, or before there is a spec.
function Compat.PrimaryStat()
    local S = GuildOS.Client.isRetail and C_SpecializationInfo
    local index = S and S.GetSpecialization and S.GetSpecialization()
    if Compat.IsSecret(index) or not index or index == 0 then return nil end
    local stat = select(6, S.GetSpecializationInfo(index))
    if Compat.IsSecret(stat) then return nil end
    stat = tonumber(stat)
    if stat == 1 or stat == 2 or stat == 4 then return stat end
    return nil
end

local SPELL_SCHOOLS = 7                                -- MAX_SPELL_SCHOOLS; school 1 is physical
local CR_VERSATILITY = CR_VERSATILITY_DAMAGE_DONE or 29 -- the rating PaperDollFrame shows

-- My ratings as the retail character sheet shows them, in percent to two decimals (issue #184):
-- crit the way PaperDollFrame takes it (the best of melee, ranged and the weakest spell school),
-- haste, mastery, and versatility's damage bonus. Nil elsewhere, where the sheet has the classic
-- stats. A rating the client cannot give, or keeps secret, is left out.
function Compat.SecondaryStats()
    if not GuildOS.Client.isRetail then return nil end
    local function read(fn, ...)
        local v = fn and fn(...)
        if Compat.IsSecret(v) then return nil end
        return tonumber(v)
    end
    local function round(v) return v and math.floor(v * 100 + 0.5) / 100 end
    local spell
    for school = 2, SPELL_SCHOOLS do
        local v = read(GetSpellCritChance, school)
        if v and (not spell or v < spell) then spell = v end
    end
    local crit
    for _, v in pairs({ spell, read(GetRangedCritChance), read(GetCritChance) }) do   -- pairs skips the nils
        if not crit or v > crit then crit = v end
    end
    local vers = read(GetCombatRatingBonus, CR_VERSATILITY)
    if vers then vers = vers + (read(GetVersatilityBonus, CR_VERSATILITY) or 0) end
    return { crit = round(crit), haste = round(read(GetHaste)), mastery = round(read(GetMasteryEffect)),
             versatility = round(vers) }
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

----------------------------------------------------------------------
-- Retail: the raid's consumables (issue #187)
----------------------------------------------------------------------
local MAX_AURAS = 40   -- buffs read per unit; retail has no such cap, so one more means the list is partial

local function inCombat() return InCombatLockdown ~= nil and InCombatLockdown() and true or false end

-- The spell ids of a unit's buffs, for the consumable check, and whether the list is all of them.
-- Midnight keeps auras secret in combat and in instances: a buff the client keeps secret, or a unit
-- token, is passed over and the list is partial, and a partial list can show a buff is there but
-- never that one is missing; so is one with a buff past the MAX_AURAS read. Nil, nothing read: in
-- combat (the check runs out of it, at the ready check and before the pull), while the client says
-- auras are secret, without the aura API, or for a unit showing no buff at all, whose auras have not
-- reached this client.
function Compat.UnitBuffIDs(unit)
    if Compat.IsSecret(unit) or inCombat() then return nil end
    local secrets = C_Secrets and C_Secrets.ShouldAurasBeSecret
    if secrets then
        local secret = secrets()
        if Compat.IsSecret(secret) or secret then return nil end
    end
    local get = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
    if not get then return nil end
    local ids, complete = {}, true
    for i = 1, MAX_AURAS + 1 do
        local a = get(unit, i)
        local present = Compat.IsSecret(a) or type(a) == "table"
        if not present then break end
        if i > MAX_AURAS or Compat.IsSecret(a) then
            complete = false
        else
            local id = a.spellId
            if Compat.IsSecret(id) or not tonumber(id) then complete = false else ids[#ids + 1] = id end
        end
    end
    if #ids == 0 and complete then return nil end
    return ids, complete
end

-- Whether my main hand carries a temporary enchant (an oil, a stone, a shaman's imbue), on retail:
-- true or false; nil elsewhere, in combat, or when the client keeps it secret. Only mine: nobody
-- else's temporary enchant reaches this client (issue #187).
function Compat.MainHandTempEnchant()
    if not (GuildOS.Client.isRetail and GetWeaponEnchantInfo) or inCombat() then return nil end
    local has = GetWeaponEnchantInfo()
    if Compat.IsSecret(has) then return nil end
    return has and true or false
end

----------------------------------------------------------------------
-- Retail: Mythic+ and the Great Vault (issue #187)
----------------------------------------------------------------------

-- Ask the client for this season's Mythic+ data; CHALLENGE_MODE_MAPS_UPDATE says it has arrived.
function Compat.RequestMythicPlus()
    if GuildOS.Client.isRetail and C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
end

-- My Mythic+ this season, on retail: { rating, key = { map, level } }, the key left out when I hold
-- none. Nil elsewhere, or when the client cannot say or keeps any of it secret, so a guildmate keeps
-- what I sent before rather than a wrong answer (issue #187).
function Compat.MythicPlus()
    if not GuildOS.Client.isRetail then return nil end
    local CM, MP = C_ChallengeMode, C_MythicPlus
    local rating = CM and CM.GetOverallDungeonScore and CM.GetOverallDungeonScore()
    if Compat.IsSecret(rating) or not tonumber(rating) then return nil end
    local map = MP and MP.GetOwnedKeystoneChallengeMapID and MP.GetOwnedKeystoneChallengeMapID()
    local level = MP and MP.GetOwnedKeystoneLevel and MP.GetOwnedKeystoneLevel()
    if Compat.IsSecret(map, level) then return nil end
    local out = { rating = math.floor(tonumber(rating) + 0.5) }
    map, level = tonumber(map), tonumber(level)
    if map and level and map > 0 and level > 0 then out.key = { map = map, level = level } end
    return out
end

-- A Mythic+ dungeon's name in the reader's language, from its challenge map id; nil when unknown.
function Compat.ChallengeMapName(map)
    local get = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo
    if not (get and tonumber(map)) then return nil end
    local name = get(tonumber(map))
    if Compat.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- The colour the game gives a Mythic+ rating, as r, g, b; nil when the client cannot say.
function Compat.RatingColor(score)
    local get = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
    if not (get and tonumber(score)) then return nil end
    local c = get(tonumber(score))
    if Compat.IsSecret(c) or type(c) ~= "table" or Compat.IsSecret(c.r, c.g, c.b) or not tonumber(c.r) then return nil end
    return c.r, c.g, c.b
end

-- The Great Vault's rows by Enum.WeeklyRewardChestThresholdType, with 12.1.5's numbers for a client
-- that does not name them. The world row is the delves' (a delve tier is its level).
local VAULT_TYPES = { Raid = { "raid", 3 }, Activities = { "dungeon", 1 }, World = { "world", 6 } }

-- My Great Vault this week, on retail: one { row, progress, threshold, level } per slot of the raid,
-- dungeon and world rows. Nil elsewhere, before the client has the activities (WEEKLY_REWARDS_UPDATE),
-- or when it keeps any of them secret (issue #187).
function Compat.WeeklyActivities()
    local get = GuildOS.Client.isRetail and C_WeeklyRewards and C_WeeklyRewards.GetActivities
    if not get then return nil end
    local enum = Enum and Enum.WeeklyRewardChestThresholdType or {}
    local rowOf = {}
    for name, v in pairs(VAULT_TYPES) do rowOf[tonumber(enum[name]) or v[2]] = v[1] end
    local list = get()
    if Compat.IsSecret(list) or type(list) ~= "table" then return nil end
    local out = {}
    for _, a in ipairs(list) do
        if Compat.IsSecret(a) or type(a) ~= "table" then return nil end
        if Compat.IsSecret(a.type, a.progress, a.threshold, a.level) then return nil end
        local row = rowOf[a.type]
        if row then
            out[#out + 1] = { row = row, progress = tonumber(a.progress) or 0, threshold = tonumber(a.threshold) or 0,
                              level = tonumber(a.level) or 0 }
        end
    end
    return #out > 0 and out or nil
end

-- When this week began, by the server's clock: the weekly reset this client's region had last. Nil
-- where the client cannot say (issue #187). The Great Vault's week, which is the game's own, so it is
-- asked of the client; RaidTracker:WeekStart(n) is the lockout week from the region table, which the
-- site shares and the self-test holds against this client (guildos-web#199).
function Compat.WeekStart()
    local get = C_DateAndTime and C_DateAndTime.GetWeeklyResetStartTime
    local at = get and get()
    if Compat.IsSecret(at) then return nil end
    return tonumber(at)
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
-- The Encounter Journal (retail, issue #185)
----------------------------------------------------------------------

-- A raid's loot as the Encounter Journal lists it: { { itemID, name, link, encounterID, boss } },
-- every class's, plus the raid's name and whether every row had its name yet (the journal fills a list
-- in as its data arrives, EJ_LOOT_DATA_RECIEVED). The journal's selection is the player's too: nothing
-- is read while it is open ("busy"), and its class and slot filters and the instance it last showed are
-- put back after. Nil on a client without the journal (Forever's has none of these).
function Compat.JournalLoot(journalInstanceID)
    local J = C_EncounterJournal
    if not (EJ_SelectInstance and EJ_GetNumLoot and J and J.GetLootInfoByIndex) then return nil end
    local open = EncounterJournal and EncounterJournal.IsShown and EncounterJournal:IsShown()
    if open then return nil, "busy" end
    local prevClass, prevSpec
    if EJ_GetLootFilter then prevClass, prevSpec = EJ_GetLootFilter() end
    local prevSlot = J.GetSlotFilter and J.GetSlotFilter()
    EJ_SelectInstance(journalInstanceID)
    if EJ_SetLootFilter then EJ_SetLootFilter(0, 0) end      -- 0, 0: every class, every spec
    if J.ResetSlotFilter then J.ResetSlotFilter() end
    local raid = EJ_GetInstanceInfo and EJ_GetInstanceInfo(journalInstanceID)
    local items, complete = {}, true
    for i = 1, EJ_GetNumLoot() or 0 do
        local info = J.GetLootInfoByIndex(i)
        if info and tonumber(info.itemID) then
            if not info.name then complete = false end
            items[#items + 1] = {
                itemID = info.itemID, name = info.name, link = info.link, encounterID = info.encounterID,
                boss = info.encounterID and EJ_GetEncounterInfo and EJ_GetEncounterInfo(info.encounterID) or nil,
            }
        end
    end
    if #items == 0 then complete = false end
    if EJ_SetLootFilter and prevClass then EJ_SetLootFilter(prevClass, prevSpec or 0) end
    if prevSlot and J.SetSlotFilter then J.SetSlotFilter(prevSlot) end
    local shown = EncounterJournal and EncounterJournal.instanceID
    if shown then
        EJ_SelectInstance(shown)
        if EncounterJournal.encounterID and EJ_SelectEncounter then EJ_SelectEncounter(EncounterJournal.encounterID) end
    end
    return items, complete, raid
end

----------------------------------------------------------------------
-- Trading a personal item (retail, issue #185)
----------------------------------------------------------------------

-- The tooltip line that says how long an item can still be traded (Enum.TooltipDataLineType, 36 in
-- 12.1.5's documentation).
local TRADE_TIME_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.TradeTimeRemaining or 36
local TRADE_SLOTS = 6   -- MAX_TRADE_ITEMS is 7: the last slot is "will not be traded"

-- Lua patterns that read a duration format ("%d |4hour:hours;") back: each grammatical form, the
-- longest first, then the format as written. Lower case, as the text is read lower case.
local function durationPatterns(fmt)
    if type(fmt) ~= "string" or fmt == "" then return {} end
    local function pattern(s)
        local escaped = s:lower():gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        return (escaped:gsub("%%%%d", "(%%d+)"))
    end
    local out = {}
    local pre, forms, post = fmt:match("^(.-)|4([^;]*);(.*)$")
    if pre then
        local list = {}
        for f in forms:gmatch("[^:]+") do list[#list + 1] = f end
        table.sort(list, function(a, b) return #a > #b end)
        for _, f in ipairs(list) do out[#out + 1] = pattern(pre .. f .. post) end
    end
    out[#out + 1] = pattern(fmt)
    return out
end

-- The seconds a trade-time line names, read with the client's own duration strings, so in any language:
-- "... for the next 1 hour 52 min." Nil when no part of it can be read.
local DURATIONS = {
    { 3600, { "INT_SPELL_DURATION_HOURS", "D_HOURS" } },
    { 60,   { "INT_SPELL_DURATION_MIN", "D_MINUTES" } },
    { 1,    { "INT_SPELL_DURATION_SEC", "D_SECONDS" } },
}
function Compat.TradeSeconds(text)
    if type(text) ~= "string" then return nil end
    text = text:lower()
    local total, found = 0, false
    for _, unit in ipairs(DURATIONS) do
        local done = false
        for _, global in ipairs(unit[2]) do
            for _, pat in ipairs(durationPatterns(_G[global])) do
                local n = tonumber(text:match(pat))
                if n then total, found, done = total + n * unit[1], true, true break end
            end
            if done then break end
        end
    end
    return found and total or nil
end

-- How long an item in my bags can still be traded: "timed", with the seconds when the line can be read
-- and the line itself; "free" when the item is not bound at all; "bound" when it can no longer be
-- traded. Nil on a client without the retail tooltip data, or for a slot with nothing in it. A personal
-- item's trade window is only on its tooltip, a line of type TradeTimeRemaining.
function Compat.TradeTimeLeft(bag, slot)
    local info = Compat.GetContainerItemInfo(bag, slot)
    if not info or Compat.IsSecret(info.isBound) then return nil end
    if not info.isBound then return "free" end
    local getter = C_TooltipInfo and C_TooltipInfo.GetBagItem
    local data = getter and getter(bag, slot)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    for _, line in ipairs(data.lines) do
        if not Compat.IsSecret(line.type) and line.type == TRADE_TIME_LINE then
            local text = line.leftText
            if Compat.IsSecret(text) or type(text) ~= "string" then return "timed" end
            return "timed", Compat.TradeSeconds(text), text
        end
    end
    return "bound"
end

-- Open a trade with a nearby player by name; false when the client has no way to (craft orders, #389).
-- InitiateTrade takes a unit: the player targeted, or one in the group (by name). For anyone else
-- it does nothing, so the caller falls back to a whisper.
function Compat.InitiateTrade(name)
    if not (InitiateTrade and type(name) == "string") then return false end
    local short = name:match("^([^-]+)") or name
    local unit
    local target = UnitName and UnitName("target")
    if target and not Compat.IsSecret(target) and (target == name or target == short) then
        unit = "target"
    elseif UnitExists and UnitExists(name) then
        unit = name
    end
    if not unit then return false end
    return pcall(InitiateTrade, unit) and true or false
end

-- Who the open trade window is with: name and realm (nil realm: this one), or nothing when the client
-- does not say or keeps it secret.
function Compat.TradePartner()
    local name, realm = UnitName("NPC")
    if Compat.IsSecret(name, realm) or type(name) ~= "string" or name == "" then return nil end
    return name, realm
end

-- The links of what I have put in the trade window, slot by slot.
function Compat.TradeItemLinks()
    local out = {}
    if not GetTradePlayerItemLink then return out end
    for i = 1, TRADE_SLOTS do
        local link = GetTradePlayerItemLink(i)
        if type(link) == "string" and not Compat.IsSecret(link) then out[#out + 1] = link end
    end
    return out
end

-- The links of what the other player has put in the trade window, slot by slot (craft orders, #389).
function Compat.TradeTargetItemLinks()
    local out = {}
    if not GetTradeTargetItemLink then return out end
    for i = 1, TRADE_SLOTS do
        local link = GetTradeTargetItemLink(i)
        if type(link) == "string" and not Compat.IsSecret(link) then out[#out + 1] = link end
    end
    return out
end

-- The trade slots I have not filled yet, in order.
function Compat.TradeFreeSlots()
    local out = {}
    if not GetTradePlayerItemLink then return out end
    for i = 1, TRADE_SLOTS do
        if not GetTradePlayerItemLink(i) then out[#out + 1] = i end
    end
    return out
end

-- Drop what the cursor holds into my trade slot `i`.
function Compat.ClickTradeButton(i)
    if ClickTradeButton then ClickTradeButton(i) end
end

-- The money I put in the trade window, in copper (no more than I have).
function Compat.SetTradeMoney(copper)
    copper = math.min(tonumber(copper) or 0, Compat.PlayerMoney())
    if SetTradeMoney and copper > 0 then SetTradeMoney(copper) end
end

----------------------------------------------------------------------
-- Bags and mail (craft orders, issue #389)
----------------------------------------------------------------------
-- The bags a player carries: the backpack, the four bags and, on retail, the reagent bag.
function Compat.BagIDs()
    local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
    local out = {}
    for b = 0, last do out[#out + 1] = b end
    return out
end

function Compat.PickupContainerItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then return C_Container.PickupContainerItem(bag, slot) end
    if PickupContainerItem then return PickupContainerItem(bag, slot) end
end

function Compat.SplitContainerItem(bag, slot, count)
    if C_Container and C_Container.SplitContainerItem then return C_Container.SplitContainerItem(bag, slot, count) end
    if SplitContainerItem then return SplitContainerItem(bag, slot, count) end
end

-- How many attachments a sent mail takes (12 on every client today).
function Compat.MailAttachMax()
    return tonumber(ATTACHMENTS_MAX_SEND) or 12
end

-- The attachment slots of the mail being written that are still empty, in order.
function Compat.MailFreeSlots()
    local out = {}
    for i = 1, Compat.MailAttachMax() do
        local name = GetSendMailItem and GetSendMailItem(i)
        if not name then out[#out + 1] = i end
    end
    return out
end

-- Drop what the cursor holds into attachment slot `i` of the mail being written.
function Compat.ClickSendMailItemButton(i)
    if ClickSendMailItemButton then ClickSendMailItemButton(i) end
end

-- Whether the mailbox shows the "Send Mail" page.
function Compat.SendMailShown()
    return SendMailFrame and SendMailFrame:IsShown() and true or false
end

-- Turn the mailbox to its "Send Mail" page.
function Compat.ShowSendMail()
    if MailFrameTab_OnClick and MailFrameTab2 then MailFrameTab_OnClick(MailFrameTab2, 2) end
end

-- The recipient and subject of the mail being written, and the money it sends (no more than I have).
function Compat.FillSendMail(to, subject, copper)
    if SendMailNameEditBox and to then SendMailNameEditBox:SetText(to) end
    if SendMailSubjectEditBox and subject then SendMailSubjectEditBox:SetText(subject) end
    copper = math.min(tonumber(copper) or 0, Compat.PlayerMoney())
    if copper > 0 then
        -- "Send Money", never C.O.D.: the send reads the money field and charges it on delivery
        -- when the C.O.D. button is the one checked.
        if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 1) end
        if SendMailMoney and MoneyInputFrame_SetCopper then MoneyInputFrame_SetCopper(SendMailMoney, copper) end
    end
end

-- Call fn(recipient, subject) each time the game sends a mail.
function Compat.HookSendMail(fn)
    if SendMail and hooksecurefunc then hooksecurefunc("SendMail", function(to, subject) fn(to, subject) end) end
end

-- Whether a UI_INFO_MESSAGE says a trade has just gone through ("Trade complete.").
function Compat.IsTradeComplete(messageType, message)
    if Compat.IsSecret(messageType, message) then return false end
    if LE_GAME_ERR_TRADE_COMPLETE ~= nil and messageType == LE_GAME_ERR_TRADE_COMPLETE then return true end
    return ERR_TRADE_COMPLETE ~= nil and message == ERR_TRADE_COMPLETE
end

-- An item's equip location ("INVTYPE_HEAD"), with no item cache needed; nil when it is not worn or the
-- client cannot say.
function Compat.EquipLoc(item)
    local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (instant and item) then return nil end
    local _, _, _, equipLoc = instant(item)
    if type(equipLoc) ~= "string" or equipLoc == "" then return nil end
    return equipLoc
end

-- The server's /roll low-high: the line everybody in the group sees (CHAT_MSG_SYSTEM, RANDOM_ROLL_RESULT).
-- False on a client without it.
function Compat.RandomRoll(low, high)
    if not RandomRoll then return false end
    return (pcall(RandomRoll, low, high))
end

-- Say a line in a chat channel: retail's C_ChatInfo.SendChatMessage, else the global. Nothing while the
-- client holds chat in lockdown (Midnight, during an encounter); returns whether it went.
function Compat.SendChatMessage(text, chatType)
    if Compat.IsSecret(text) or (Compat.InChatLockdown and Compat.InChatLockdown()) then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, text, chatType))
end

-- Whisper one line to `target`, as a click of the player sends it (issue #403). Nothing in a chat lockdown;
-- returns whether it went. The target's "No player named" line is the caller's to note (NoteWhisper).
function Compat.SendWhisper(text, target)
    if not target or target == "" or Compat.IsSecret(text) then return false end
    if Compat.InChatLockdown and Compat.InChatLockdown() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, text, "WHISPER", nil, target))
end

-- Lets `fn` hide lines of a chat event from every chat frame: retail moved the filter to ChatFrameUtil, and
-- the global is a deprecation fallback there. False on a client with neither.
function Compat.AddChatFilter(event, fn)
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then return false end
    add(event, fn)
    return true
end

-- Does a chat frame show a message group ("GUILD")? Retail moved the check to ChatFrameUtil; a client with
-- neither is read from the frame's own list (issue #344).
function Compat.ChatFrameShows(frame, group)
    if not frame then return false end
    local has = (ChatFrameUtil and ChatFrameUtil.ContainsMessageGroup) or ChatFrame_ContainsMessageGroup
    if has then
        local ok, yes = pcall(has, frame, group)
        return ok and yes and true or false
    end
    for _, g in ipairs(frame.messageTypeList or {}) do
        if g == group then return true end
    end
    return false
end

-- A line in a custom channel by its number. The game takes it only from a key press, so this is only ever
-- called from one (issue #348). Nothing in a chat lockdown.
function Compat.SendChannelMessage(text, index)
    if not index or index == 0 or Compat.IsSecret(text) then return false end
    if Compat.InChatLockdown and Compat.InChatLockdown() then return false end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, text, "CHANNEL", nil, index))
end

-- Join a channel with a password without the client saving it for the next login (issue #348).
function Compat.JoinPrivateChannel(name, password)
    local join = JoinTemporaryChannel or JoinChannelByName
    if not join or not name then return false end
    return (pcall(join, name, password))
end

-- Take a channel out of every chat frame that lists it, so its lines never print there (issue #348).
function Compat.RemoveChannelFromFrames(name)
    local remove = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or ChatFrame_RemoveChannel
    if not remove or not GetChatWindowChannels or not name then return 0 end
    local n = 0
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        local list = { GetChatWindowChannels(i) }
        for j = 1, #list, 2 do
            if type(list[j]) == "string" and list[j]:lower() == name:lower() and frame then
                if pcall(remove, frame, list[j]) then n = n + 1 end
            end
        end
    end
    return n
end

-- `fn(chatType, text)` for every line the player sends from a chat box, called inside the key press that
-- sends it (a post-hook of the box's ParseText), which is what lets `fn` post to a channel. Patch 1.15.9 and
-- retail 11 moved ParseText onto each box; older clients have the global (issue #348).
function Compat.HookChatSend(fn)
    local function onParse(box, send)
        if send ~= 1 or not box or not box.GetAttribute then return end
        local chatType, text = box:GetAttribute("chatType"), box:GetText()
        if Compat.IsSecret(chatType, text) then return end
        if type(text) == "string" and text:match("%S") then fn(chatType, text) end
    end
    if ChatFrame1EditBox and ChatFrame1EditBox.ParseText then
        local n = 0
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local box = _G["ChatFrame" .. i .. "EditBox"]
            if box and box.ParseText then
                hooksecurefunc(box, "ParseText", onParse)
                n = n + 1
            end
        end
        return n > 0
    end
    if ChatEdit_ParseText then
        hooksecurefunc("ChatEdit_ParseText", onParse)
        return true
    end
    return false
end

-- Hand `frame` a chat event as if the game had sent it, through the frame's own handler, so the line is
-- drawn exactly as the game draws that event (issue #348). False when the frame has no handler or it errored.
function Compat.ReplayChatEvent(frame, event, ...)
    if not frame then return false end
    local handler = ChatFrame_MessageEventHandler
    if type(handler) ~= "function" and frame.GetScript then handler = frame:GetScript("OnEvent") end
    if type(handler) ~= "function" then return false end
    return (pcall(handler, frame, event, ...))
end

-- Is `name` on the player's ignore list? C_FriendList where it exists, the old global elsewhere (issue #344).
function Compat.IsIgnored(name)
    if type(name) ~= "string" or name == "" or Compat.IsSecret(name) then return false end
    local is = (C_FriendList and C_FriendList.IsIgnored) or IsIgnored
    if not is then return false end
    local ok, yes = pcall(is, name)
    return ok and yes and true or false
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

-- Invite somebody to the group. The retail client moved it to C_PartyInfo and dropped
-- the globals; WoW: Forever has only C_PartyInfo, and its own /invite uses it (issue #43).
function Compat.InviteUnit(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then return C_PartyInfo.InviteUnit(name) end
    if InviteUnit then return InviteUnit(name) end
    if InviteByName then return InviteByName(name) end
end

-- An instance's name in the player's own language, by its map id, or nil where the client does not
-- know the instance (issue #341). Never a secret value: it is shown and compared.
function Compat.InstanceName(mapID)
    if not GetRealZoneText or type(mapID) ~= "number" then return nil end
    local ok, name = pcall(GetRealZoneText, mapID)
    if ok and type(name) == "string" and name ~= "" and not Compat.IsSecret(name) then return name end
    return nil
end

-- Whether the client has this texture file. A path it does not have draws a green square, so art
-- that is only a guess at the client's files is drawn when this answers true and never otherwise:
-- with no way to ask, the answer is no (issue #341).
function Compat.TextureExists(path)
    if not GetFileIDFromPath or type(path) ~= "string" then return false end
    local ok, id = pcall(GetFileIDFromPath, path)
    return ok and type(id) == "number" and id > 0
end

-- Who is in my party or raid besides me, as a set of player keys, and how many of us there are (1
-- alone). A member whose name the client will not tell yet is counted and not named. On WoW: Forever
-- nobody has seen whether a unit's name carries the surname, joined or in the realm's slot (issue
-- #48), so each member is also there under "~" and their first name, for Compat.InGroup (issue #341).
function Compat.GroupRoster()
    local members, count = {}, 1
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 1 then return members, count end
    local raid = IsInRaid and IsInRaid()
    local surnames = GuildOS.Client.has.surnames
    local me = Compat.PlayerName()
    count = n
    for i = 1, raid and n or (n - 1) do
        local name, second = Compat.UnitIdentity((raid and "raid" or "party") .. i)
        if type(name) == "string" and name ~= "" then
            if type(second) ~= "string" or second == "" then second = nil end
            local whole, realm = name, second
            if surnames then
                whole, realm = (second and not name:find(" ", 1, true)) and (name .. " " .. second) or name, nil
            end
            if whole ~= me then
                local key = GuildOS:GetPlayerKey(whole, realm or GetRealmName())
                if key then members[key] = true end
                if surnames then members["~" .. (whole:match("^%S+") or whole)] = true end
            end
        end
    end
    return members, count
end

-- Turn my party into a raid (issue #378): C_PartyInfo's where the client has it, the old global
-- otherwise. False where neither exists or the game refuses.
function Compat.ConvertToRaid()
    local convert = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
    if not convert then return false end
    return (pcall(convert))
end

-- Move raid member `index` into raid group `group` (1 to 8), or swap two members' groups (issue #400). Both are
-- still globals: retail 12.1.5's probe found SetRaidSubgroup, WoW: Forever's API documentation is retail's, and
-- neither moved into C_PartyInfo the way InviteUnit and ConvertToRaid did. False where the call is missing or raises.
function Compat.SetRaidSubgroup(index, group)
    if not SetRaidSubgroup then return false end
    return (pcall(SetRaidSubgroup, index, group))
end
function Compat.SwapRaidSubgroup(index1, index2)
    if not SwapRaidSubgroup then return false end
    return (pcall(SwapRaidSubgroup, index1, index2))
end
-- Whether this client can swap two raid members at all: without it a full group takes nobody, and the raid's
-- arranging plans no swap it could not make (issue #400).
function Compat.CanSwapRaidSubgroup()
    return SwapRaidSubgroup ~= nil
end

-- One of the player's group flags (UnitIsGroupLeader, UnitIsGroupAssistant), read past the Secret Values: WoW:
-- Forever and retail answer them secret when the unit's identity is restricted (docs/forever), and a secret is
-- never tested, so it counts as no. False where the call is missing or raises.
local function playerFlag(fn)
    if not fn then return false end
    local ok, v = pcall(fn, "player")
    if not ok or Compat.IsSecret(v) then return false end
    return v and true or false
end

-- Whether I lead my group (issue #400). False outside a group, and when the client keeps the answer secret.
function Compat.IsGroupLeader()
    if ((GetNumGroupMembers and GetNumGroupMembers()) or 0) == 0 then return false end
    return playerFlag(UnitIsGroupLeader)
end

-- Whether I may invite and arrange (issue #400): alone, with no group yet, the one to start it; my group's
-- leader; or a raid's assistant. A secret answer counts as no and never raises.
function Compat.IsLeaderOrAssist()
    local n = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if n <= 1 then return true end
    return playerFlag(UnitIsGroupLeader) or playerFlag(UnitIsGroupAssistant)
end

-- A ready check (issue #378): the leader's or an assistant's, where the client has it.
function Compat.CanReadyCheck()
    return DoReadyCheck ~= nil
end
function Compat.DoReadyCheck()
    if not DoReadyCheck then return false end
    return (pcall(DoReadyCheck))
end

-- Whether I may invite somebody: alone, the group's leader, or a raid's assistant (issue #341), read past the
-- Secret Values since issue #400.
function Compat.CanInvite()
    return Compat.IsLeaderOrAssist()
end

-- Whether the player of this key is in a roster Compat.GroupRoster gave. On WoW: Forever the first
-- name decides when the whole name does not match: a guildmate who shares it would read as there,
-- and a spot left open by mistake is worse than one closed a moment early.
function Compat.InGroup(members, key)
    if members[key] then return true end
    if not GuildOS.Client.has.surnames then return false end
    return members["~" .. (key:match("^([^%s%-]+)") or key)] == true
end

-- Remove somebody from the group: C_PartyInfo's where the client has it, the old global otherwise
-- (issue #292, as InviteUnit above).
function Compat.UninviteUnit(name)
    if C_PartyInfo and C_PartyInfo.UninviteUnit then return C_PartyInfo.UninviteUnit(name) end
    if UninviteUnit then return UninviteUnit(name) end
end

-- r, g, b, hex for an item quality: C_Item's, or the old global's, or white (issue #43).
function Compat.GetItemQualityColor(quality)
    if C_Item and C_Item.GetItemQualityColor then return C_Item.GetItemQualityColor(quality) end
    if GetItemQualityColor then return GetItemQualityColor(quality) end
    return 1, 1, 1, "ffffffff"
end

-- How many of an item the player carries: C_Item's count, or the old global's (issue #43).
function Compat.GetItemCount(item, includeBank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(item, includeBank or false) end
    if GetItemCount then return GetItemCount(item, includeBank) end
    return 0
end

-- A dialog's edit box. GuildOS's own dialog (GuildOS:ShowDialog, #315) keeps it at `editBox`, as
-- Anniversary's StaticPopup did; WoW: Forever's popup (the
-- retail one) at `EditBox`, behind `GetEditBox()`, with `editBox` nil (issue #49).
function Compat.PopupEditBox(dialog)
    if not dialog then return nil end
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox or dialog.EditBox
end

-- WoW: Forever has no talent tabs: each class is one trait tree (issue #41). Returns the
-- active tree's nodes as { {x = posX, points = ranks bought}, ... }, or nil and why:
-- "no-api" on a client with no trait trees at all, "no-config" before the talents have
-- loaded or been unlocked. Anniversary never gets here: it has GetNumTalentTabs.
function Compat.TraitTreeNodes()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
            and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
        return nil, "no-api"
    end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil, "no-config" end
    local nodes = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.posX then
            nodes[#nodes + 1] = { x = info.posX, points = tonumber(info.ranksPurchased) or 0 }
        end
    end
    return nodes
end

-- The talents bought on a trait tree, as { {definitionID, rank}, ... } sorted by definitionID, only
-- the nodes with a rank (issue #399). The definitionID is the talent's own id in the game's tables,
-- which does not move when the tree is redrawn; on a choice node it is the chosen entry's. configID
-- nil reads the player's active tree; an inspect config reads the inspected unit's. Nil and why:
-- "no-api" without the trait API (or without that config), "no-config" before the tree has loaded,
-- "no-points" when nothing is bought, so a caller never publishes an empty tree it did not read.
local function traitTalents(configID)
    if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo
            and C_Traits.GetEntryInfo) then
        return nil, "no-api"
    end
    if configID == nil then
        if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return nil, "no-api" end
        configID = C_ClassTalents.GetActiveConfigID()
    end
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil, "no-config" end
    local out = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        local rank = info and tonumber(info.currentRank or info.ranksPurchased) or 0
        local entryID = info and type(info.activeEntry) == "table" and info.activeEntry.entryID
        if rank > 0 and entryID then
            local entry = C_Traits.GetEntryInfo(configID, entryID)
            local def = entry and tonumber(entry.definitionID)
            if def and def > 0 then out[#out + 1] = { math.floor(def), math.floor(rank) } end
        end
    end
    if #out == 0 then return nil, "no-points" end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

function Compat.TraitTalents(configID)
    local ok, talents, why = pcall(traitTalents, configID)
    if not ok then return nil, "error" end
    return talents, why
end

-- The config id the trait API reads an inspected unit's tree from, after INSPECT_READY. Nil on a
-- client that does not expose one: the inspect then brings no talents.
function Compat.InspectTraitConfigID()
    local consts = Constants and Constants.TraitConsts
    return consts and tonumber(consts.INSPECT_TRAIT_CONFIG_ID) or nil
end

-- A unit's spec on retail (ADR-0026), where a character has one and the client names it: the spec
-- id, its name in the reader's language and its role ("TANK", "HEALER", "DAMAGER"). "player" is
-- read directly; any other unit is read from its inspect, so it needs INSPECT_READY first. Nil
-- before there is a spec, or when the client keeps the unit's identity secret.
function Compat.SpecOf(unit)
    local S = C_SpecializationInfo
    if unit == "player" then
        local index = S and S.GetSpecialization and S.GetSpecialization()
        if Compat.IsSecret(index) or not index or index == 0 then return nil end
        local id, name, _, _, role = S.GetSpecializationInfo(index)
        if Compat.IsSecret(id, name, role) or not id or id == 0 then return nil end
        return id, name, role
    end
    local id = S and S.GetInspectSpecialization and S.GetInspectSpecialization(unit)
    if Compat.IsSecret(id) or not id or id == 0 or not GetSpecializationInfoForSpecID then return nil end
    local _, name, _, _, role = GetSpecializationInfoForSpecID(id)
    if Compat.IsSecret(name, role) then return nil end
    return id, name, role
end

-- A retail spec's name in the reader's language, from its id: a spec synced from a guildmate's
-- client arrives in theirs (issue #177). Nil when the client cannot say.
function Compat.SpecName(id)
    if not (tonumber(id) and GetSpecializationInfoForSpecID) then return nil end
    local _, name = GetSpecializationInfoForSpecID(id)
    if Compat.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
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
-- Professions on the retail tradeskill API (WoW: Forever, issue #31)
----------------------------------------------------------------------

-- The spell-book indices of the player's professions (two primaries, First Aid, Fishing,
-- Cooking, ...), nils included; nothing on a client without the API.
function Compat.GetProfessions()
    if not GetProfessions then return end
    return GetProfessions()
end

-- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, ... for a GetProfessions index.
function Compat.GetProfessionInfo(index)
    if not GetProfessionInfo then return nil end
    return GetProfessionInfo(index)
end

-- Whether the player knows a spell. On Forever this answers for a recipe with the profession
-- window closed (verified 2026-09-27); C_SpellBook.IsSpellInSpellBook does not.
function Compat.IsPlayerSpell(spellID)
    if not IsPlayerSpell then return false end
    return IsPlayerSpell(spellID) and true or false
end

-- The profession window's skill line and learned recipe IDs, when it shows the player's OWN
-- profession and its data has settled. Nothing for a linked or guild view, a window still
-- loading, or a client without the API.
function Compat.TradeSkillLearned()
    local T = C_TradeSkillUI
    if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetBaseProfessionInfo) then return nil end
    if T.IsDataSourceChanging and T.IsDataSourceChanging() then return nil end
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember()) then
        return nil
    end
    local base = T.GetBaseProfessionInfo()
    local line = base and base.professionID
    if not line or line == 0 then return nil end
    local learned = {}
    for _, id in ipairs(T.GetAllRecipeIDs() or {}) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned then learned[#learned + 1] = id end
    end
    return line, learned
end

-- The parent skill line a recipe belongs to (GetTradeSkillLineForRecipe returns the child
-- line, its name, then the parent), for a recipe the catalog does not know yet.
function Compat.RecipeLine(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetTradeSkillLineForRecipe) then return nil end
    local _, _, parent = T.GetTradeSkillLineForRecipe(recipeID)
    return parent
end

-- Every guild member's primary professions as the Communities roster reports them, addon or
-- not: { { name = "First Last", lines = { skillLine, ... } }, ... }. The rank it gives is always
-- 1 on Forever and is left out. Secret fields (chat messaging lockdown) skip the member.
function Compat.GuildMemberProfessions()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return nil end
    local ids = C_Club.GetClubMembers(clubId)
    if Compat.IsSecret(ids) or type(ids) ~= "table" then return nil end
    local out = {}
    for _, memberId in ipairs(ids) do
        local m = C_Club.GetMemberInfo(clubId, memberId)
        if m and not Compat.IsSecret(m.name, m.profession1ID, m.profession2ID) and type(m.name) == "string" then
            local lines = {}
            if type(m.profession1ID) == "number" and m.profession1ID > 0 then lines[#lines + 1] = m.profession1ID end
            if type(m.profession2ID) == "number" and m.profession2ID > 0 then lines[#lines + 1] = m.profession2ID end
            out[#out + 1] = { name = m.name, lines = lines }
        end
    end
    return out
end

----------------------------------------------------------------------
-- The guild's chat as the server keeps it (WoW: Forever, issue #126): the streams of the guild's
-- club, which the Communities window reads. They hold what was said while the player was offline,
-- which no chat event delivers. Measured on Forever: a message is { messageId = { epoch, position },
-- author = { name, classID }, content }, the epoch in microseconds, and no timestamp field.
--
-- In a chat lockdown the lists, ranges and messages arrive secret (SecretInChatMessagingLockdown in
-- ClubDocumentation.lua), so none of them is read then. Focusing a stream is not restricted, and
-- the guild's /g stream is remembered from the last read for it.
----------------------------------------------------------------------
local guildStreamOf = {}   -- clubId -> the /g stream's id, from the last list read

local function guildClub()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams and C_Club.GetMessageRanges) then return nil end
    local clubId = C_Club.GetGuildClubId()
    if not clubId or Compat.IsSecret(clubId) then return nil end
    return clubId
end

-- The guild's channels as the game lists them to this player, as { id, name, kind }: "guild",
-- then "officer" (listed only to who may read it), then the ones the guild made ("other"), in the
-- server's order. General and Discord streams are not the guild's to chat in here. Nil where the
-- client has no guild club; nil, "locked" in a chat lockdown.
function Compat.GuildChatStreams()
    local clubId = guildClub()
    if not clubId then return nil end
    if Compat.InChatLockdown() then return nil, "locked" end
    local T = Enum and Enum.ClubStreamType or {}
    local kinds = { [T.Guild or 1] = "guild", [T.Officer or 2] = "officer", [T.Other or 4] = "other" }
    local rank = { guild = 1, officer = 2, other = 3 }
    local out = {}
    for _, s in ipairs(C_Club.GetStreams(clubId) or {}) do
        local kind = not Compat.IsSecret(s.streamId, s.name, s.streamType) and kinds[s.streamType]
        if kind then
            out[#out + 1] = { id = s.streamId, name = s.name, kind = kind, order = #out }
            if kind == "guild" then guildStreamOf[clubId] = s.streamId end
        end
    end
    table.sort(out, function(a, b)
        if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
        return a.order < b.order
    end)
    return out
end

-- The stream to read: the one asked for, or the guild's own.
local function streamOf(streamId)
    local clubId = guildClub()
    if not clubId then return nil end
    if streamId then return clubId, streamId end
    if not guildStreamOf[clubId] and not Compat.InChatLockdown() then Compat.GuildChatStreams() end
    if guildStreamOf[clubId] then return clubId, guildStreamOf[clubId] end
    return nil
end

-- The newest range of messages the client holds, as Blizzard_Communities picks it; nil when there
-- is none, or it is empty (its newest before its oldest).
local function newestRange(clubId, streamId)
    local ranges = C_Club.GetMessageRanges(clubId, streamId) or {}
    local r = ranges[#ranges]
    if not r then return nil end
    local o, n = r.oldestMessageId, r.newestMessageId
    if n.epoch < o.epoch or (n.epoch == o.epoch and n.position < o.position) then return nil end
    return r
end

-- True when a club event is about the guild's club, any of its channels, and not another club.
function Compat.IsGuildClub(clubId)
    if Compat.IsSecret(clubId) then return false end
    local c = guildClub()
    return c ~= nil and c == clubId
end

-- The last `max` lines of a channel (the guild's own when none is named), oldest first, as
-- { t, n, c, m } like the addon's own log. Nil where the client has no guild club; nil, "locked"
-- in a chat lockdown. A deleted message, or one whose text, speaker or time is secret, is left out.
function Compat.GuildChatHistory(max, streamId)
    if not guildClub() then return nil end
    if Compat.InChatLockdown() then return nil, "locked" end
    local clubId, sid = streamOf(streamId)
    if not clubId or not C_Club.GetMessagesBefore then return {} end
    local r = newestRange(clubId, sid)
    if not r then return {} end
    local out = {}
    for _, msg in ipairs(C_Club.GetMessagesBefore(clubId, sid, r.newestMessageId, max) or {}) do
        local a, id = msg.author, msg.messageId
        if a and id and not Compat.IsSecret(msg.destroyed, id.epoch, msg.content, a.name, a.classID)
            and not msg.destroyed and type(msg.content) == "string" and type(a.name) == "string" then
            local class = a.classID and GetClassInfo and select(2, GetClassInfo(a.classID))
            out[#out + 1] = {
                t = math.floor(id.epoch / 1e6),
                n = a.name,
                c = class,
                m = (msg.content:gsub("%c", " ")),
            }
        end
    end
    return out
end

-- A channel is open (true) or closed: the server is told it is being read, as the Communities
-- window does when it shows one.
function Compat.WatchGuildChat(on, streamId)
    local clubId, sid = streamOf(streamId)
    if not clubId then return end
    if on and C_Club.FocusStream then
        C_Club.FocusStream(clubId, sid)
    elseif not on and C_Club.UnfocusStream then
        C_Club.UnfocusStream(clubId, sid)
    end
end

-- `count` lines older than the oldest held; they arrive with CLUB_MESSAGE_HISTORY_RECEIVED. With
-- nothing held, the recent ones, as Blizzard_Communities asks for them (no message, no count).
function Compat.RequestOlderGuildChat(count, streamId)
    if Compat.InChatLockdown() then return end
    local clubId, sid = streamOf(streamId)
    if not clubId or not C_Club.RequestMoreMessagesBefore then return end
    local r = newestRange(clubId, sid)
    if r then
        C_Club.RequestMoreMessagesBefore(clubId, sid, r.oldestMessageId, count)
    else
        C_Club.RequestMoreMessagesBefore(clubId, sid, nil)
    end
end

-- A line to a channel the guild made: /g and /o have their own chat types, these only the club's
-- own send. False when the channel is no longer listed.
function Compat.SendGuildStream(streamId, text)
    local clubId = guildClub()
    if not clubId or not C_Club.SendMessage then return false end
    for _, s in ipairs(Compat.GuildChatStreams() or {}) do
        if s.id == streamId then
            C_Club.SendMessage(clubId, streamId, text)
            return true
        end
    end
    return false
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
-- WoW: Forever's chat lockdown, false on a client without one (#124).
Compat.InChatLockdown = inLockdown

local function record(msg, reason)
    reason = tostring(reason)
    if Compat._reported[reason] then return end
    Compat._reported[reason] = true
    GuildOS:RecordError(string.format("Addon message on %s was not sent (result %s)", tostring(msg.channel), reason))
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
    if didSend or result == SUCCESS then
        -- What has to follow the message, once it is really out (the loot council's /roll, issue #185).
        if msg.onSent then pcall(msg.onSent) end
        return
    end
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

-- Does a chat line, a guild invite or a /who need a click behind it? On WoW: Forever the game
-- drops them when an addon starts them from a timer or an event, without an error: in game
-- (2026-10-02, build 1.60.1.70170) a GUILD line from a C_Timer callback went nowhere, and an
-- auto-invite answering a whisper printed but invited nobody, while the same invite from an
-- Alt-click worked. SendChatMessage and SendWho are HasRestrictions there. Anniversary does
-- them on its own. Anything that has to happen by itself asks for the click on Forever (#61).
function Compat.NeedsClick()
    return not GuildOS.Client.isAnniversary
end

-- A guild invite (#256). Only TBC Anniversary lets an addon invite to the guild. WoW: Forever
-- 1.60.1.70790 refused all three ways one has, in game on 2026-11-04: GuildInvite itself, which is only
-- C_GuildInfo.Invite there (ADDON_ACTION_FORBIDDEN, from a click too); a secure button running a
-- /ginvite the addon wrote (MACRO_ACTION_BLOCKED); and that line left in the chat box for the player's
-- Enter (blocked, and the box stayed tainted until a /reload). Retail runs the same API. So off
-- Anniversary nothing offers an invite, and what still asks for one is told the /ginvite line to type.
function Compat.AddonMayInvite()
    return GuildOS.Client.isAnniversary == true and CanGuildInvite() == true
end

function Compat.GuildInvite(name)
    if type(name) ~= "string" or name == "" then return false end
    if GuildOS.Client.isAnniversary then GuildInvite(name); return true end
    GuildOS:Print(string.format(GuildOS.L["Type /ginvite %s to invite them."], name))
    return false
end

-- Does the server show this channel without raid icons? It is the ChatChannels table's
-- DisableRaidIcons flag, which the chat event hands the client as suppressRaidIcons. On WoW:
-- Forever (1.60.1.70170) that is General 1, Trade 2, LocalDefense 22, Services 42 and
-- TradeLocal 46 (LookingForGroup is not); on Anniversary no channel. By zone channel id, so it
-- holds in every language; a custom channel has none (issue #64).
local NO_RAID_ICONS = { [1] = true, [2] = true, [22] = true, [42] = true, [46] = true }
function Compat.ChannelHidesRaidIcons(name, number)
    if GuildOS.Client.isAnniversary then return false end
    local get = C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier
    if not get then return false end
    local info = get(tostring(name or "")) or (number and get(tostring(number)))
    return info ~= nil and NO_RAID_ICONS[info.zoneChannelID] == true
end

-- Send an addon message through ChatThrottleLib; prio is its "BULK" (default), "NORMAL" or "ALERT".
function Compat.SendAddonMessage(prefix, text, channel, target, prio, queueName)
    queue({ prefix = prefix, text = text, channel = channel, target = target,
            prio = prio or "BULK", queue = queueName, tries = 1 })
end

-- Send an addon message now, past ChatThrottleLib's queue, with the same results: loot, whose timers start at send.
-- `onSent`, optional, runs once the message has really gone out: not while a lockdown holds it or a
-- throttle retries it, and never for one that is dropped.
function Compat.SendAddonMessageNow(prefix, text, channel, target, onSent)
    queue({ prefix = prefix, text = text, channel = channel, target = target, prio = "ALERT", now = true, tries = 1,
            onSent = onSent })
end

----------------------------------------------------------------------
-- Created channels. A channel is joined by name and addressed by the number the game gives it; both
-- calls are the same on retail and WoW: Forever, and neither is trusted to exist or to answer.
----------------------------------------------------------------------

-- Joins `name`, creating it when nobody has. True when the call went; the number comes from ChannelId.
function Compat.JoinChannel(name)
    if not JoinChannelByName then return false end
    return (pcall(JoinChannelByName, name))
end

-- The number of the channel `name` as this client has it, 0 when it is not joined (or the game keeps it secret).
function Compat.ChannelId(name)
    if not GetChannelName then return 0 end
    local ok, id = pcall(GetChannelName, name)
    id = ok and not Compat.IsSecret(id) and tonumber(id) or 0
    return id
end

-- Leaves `name`. True when the call went, whether or not the channel was joined.
function Compat.LeaveChannel(name)
    if not LeaveChannelByName then return false end
    return (pcall(LeaveChannelByName, name))
end

----------------------------------------------------------------------
-- The game's own calendar (guildos-web specs/075, guildos#263). Measured on WoW: Forever 1.60.1.70790:
-- reading is free; creating and editing need a hardware event (from a timer the game raises
-- ADDON_ACTION_BLOCKED); a guild event with sign-up is the only guild kind there is (no announcements,
-- not even for the GM). The calendar keeps the realm's clock; the site and the rest of the addon keep
-- UTC epochs. TBC Anniversary and retail were not measured, so nothing is offered there.
----------------------------------------------------------------------
local QUARTER_HOUR = 900
local DAY = 86400

-- Days since 1970-01-01 for a civil date, and back (H. Hinnant's algorithm): plain arithmetic, so the
-- PC's own time zone never enters a calendar sum.
local function daysFromCivil(y, m, d)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function civilFromDays(z)
    z = z + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400
    if m <= 2 then y = y + 1 end
    return y, m, d
end

local function fieldsAsEpoch(y, m, d, h, mi)
    return daysFromCivil(y, m, d) * DAY + (h or 0) * 3600 + (mi or 0) * 60
end

function Compat.CalendarAvailable()
    local client = GuildOS.Client or {}
    return not client.isAnniversary and not client.isRetail
        and type(C_Calendar) == "table" and type(C_Calendar.AddEvent) == "function"
end

-- How far the realm's clock is from UTC, in seconds, to the quarter hour (the two clocks are read a
-- moment apart).
function Compat.RealmOffset()
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if type(now) ~= "table" then return 0 end
    local diff = fieldsAsEpoch(now.year, now.month, now.monthDay, now.hour, now.minute) - GetServerTime()
    return math.floor(diff / QUARTER_HOUR + 0.5) * QUARTER_HOUR
end

--- The date and the time a UTC instant has on the realm's calendar.
function Compat.RealmClock(epochUtc)
    local realm = epochUtc + Compat.RealmOffset()
    local days = math.floor(realm / DAY)
    local rest = realm - days * DAY
    local y, m, d = civilFromDays(days)
    return { year = y, month = m, day = d, hour = math.floor(rest / 3600), minute = math.floor((rest % 3600) / 60) }
end

--- The UTC instant of a date and time on the realm's calendar.
function Compat.EpochOfRealm(t)
    return fieldsAsEpoch(t.year, t.month, t.day, t.hour, t.minute) - Compat.RealmOffset()
end

local GUILD_KINDS = { GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true }
local CALENDAR_REQUEST_EVERY = 60   -- seconds between two requests for the calendar's events

-- The game hands its calendar over only after OpenCalendar, and answers with CALENDAR_UPDATE_EVENT_LIST.
-- Until that first answer the events are unknown, never none: an empty read would show every raid as
-- missing from the game and invite a second event. Asking is kept apart from reading, so reading inside
-- that event's own handler never asks again (a request loop).
local calendarRead, lastCalendarRequest = false, nil
Compat._calendarListeners = {}
local calendarWatch = CreateFrame("Frame")
Compat.RegisterEvent(calendarWatch, "CALENDAR_UPDATE_EVENT_LIST")
calendarWatch:SetScript("OnEvent", function()
    calendarRead = true
    for _, fn in ipairs(Compat._calendarListeners) do pcall(fn) end
end)

--- Asks the game for its calendar's events, at most once a CALENDAR_REQUEST_EVERY seconds.
function Compat.CalendarRequest()
    if not Compat.CalendarAvailable() then return end
    local now = GetTime()
    if lastCalendarRequest and now - lastCalendarRequest < CALENDAR_REQUEST_EVERY then return end
    lastCalendarRequest = now
    pcall(C_Calendar.OpenCalendar)
end

--- Calls `fn` each time the game's calendar answers with its events.
function Compat.OnCalendarUpdate(fn)
    Compat._calendarListeners[#Compat._calendarListeners + 1] = fn
end

--- The guild's events between two UTC instants, holidays and personal events left out:
--- { offset, day, index, title, calendarType, startsAt }; nil while the game has not read its calendar
--- yet (Compat.CalendarRequest asks). The calendar reads months relative to the one its window shows, so
--- the offsets are worked out from that month, never assumed to start at today's.
function Compat.CalendarGuildEvents(fromEpoch, toEpoch)
    local out = {}
    if not Compat.CalendarAvailable() then return out end
    if not calendarRead then return nil end
    local okShown, shown = pcall(C_Calendar.GetMonthInfo, 0)
    if not okShown or type(shown) ~= "table" then return out end
    local base = shown.year * 12 + shown.month - 1
    local first, last = Compat.RealmClock(fromEpoch), Compat.RealmClock(toEpoch)
    for idx = first.year * 12 + first.month - 1, last.year * 12 + last.month - 1 do
        local offset = idx - base
        local okInfo, info = pcall(C_Calendar.GetMonthInfo, offset)
        for day = 1, (okInfo and type(info) == "table" and info.numDays or 0) do
            local okN, n = pcall(C_Calendar.GetNumDayEvents, offset, day)
            for index = 1, (okN and tonumber(n) or 0) do
                local okE, e = pcall(C_Calendar.GetDayEvent, offset, day, index)
                if okE and type(e) == "table" and GUILD_KINDS[e.calendarType] and type(e.startTime) == "table"
                    and not Compat.IsSecret(e.title) then
                    local s = e.startTime
                    local startsAt = Compat.EpochOfRealm({ year = s.year, month = s.month, day = s.monthDay, hour = s.hour, minute = s.minute })
                    if startsAt >= fromEpoch and startsAt <= toEpoch then
                        out[#out + 1] = { offset = offset, day = day, index = index, title = tostring(e.title),
                                          calendarType = e.calendarType, startsAt = startsAt }
                    end
                end
            end
        end
    end
    return out
end

-- The event being edited, onto the calendar's date and time: the raid's clock as it was created when
-- the site gave one (guildos-web #411: the guild reads the game's calendar as its Discord's time, so the
-- numbers typed there go in as they are), else the instant on the realm's clock.
local function setEventWhen(spec)
    local t = type(spec.clock) == "table" and spec.clock or Compat.RealmClock(spec.startsAt)
    C_Calendar.EventSetDate(t.month, t.day, t.year)
    C_Calendar.EventSetTime(t.hour, t.minute)
end

--- A guild event with sign-up: { title, description, startsAt }. Only from a click; true, or false
--- and why. The answer from the server comes later, as CALENDAR_UPDATE_ERROR or a new event.
function Compat.CalendarCreateGuildEvent(spec)
    if not Compat.CalendarAvailable() then return false, "unavailable" end
    local ok, err = pcall(function()
        C_Calendar.CreateGuildSignUpEvent()
        C_Calendar.EventSetTitle(spec.title)
        C_Calendar.EventSetDescription(spec.description or "")
        setEventWhen(spec)
        local raid = Enum and Enum.CalendarEventType and Enum.CalendarEventType.Raid
        if raid and C_Calendar.EventSetType then C_Calendar.EventSetType(raid) end
        C_Calendar.AddEvent()
    end)
    if not ok then return false, tostring(err) end
    return true
end

--- Opens the event at `where` ({ offset, day, index }) for editing; the game answers CALENDAR_OPEN_EVENT.
function Compat.CalendarOpenEvent(where)
    if not Compat.CalendarAvailable() then return false, "unavailable" end
    local ok, res = pcall(C_Calendar.OpenEvent, where.offset, where.day, where.index)
    if not ok then return false, tostring(res) end
    return res ~= false
end

--- The event the game has open for editing, as { title, startsAt }, or nil.
function Compat.CalendarOpenedEvent()
    if not Compat.CalendarAvailable() or not C_Calendar.GetEventInfo then return nil end
    local ok, info = pcall(C_Calendar.GetEventInfo)
    if not ok or type(info) ~= "table" or type(info.title) ~= "string" or Compat.IsSecret(info.title) then return nil end
    local t = info.time
    if type(t) ~= "table" then return nil end
    return { title = info.title,
             startsAt = Compat.EpochOfRealm({ year = t.year, month = t.month, day = t.monthDay, hour = t.hour, minute = t.minute }) }
end

--- Saves { title, startsAt, description } onto the open event, from a click, and closes it. With no
--- description the one in the game stays as people wrote it.
function Compat.CalendarApplyEdit(spec)
    if not Compat.CalendarAvailable() then return false, "unavailable" end
    local ok, err = pcall(function()
        C_Calendar.EventSetTitle(spec.title)
        if spec.description ~= nil then C_Calendar.EventSetDescription(spec.description) end
        setEventWhen(spec)
        C_Calendar.UpdateEvent()
    end)
    pcall(C_Calendar.CloseEvent)
    if not ok then return false, tostring(err) end
    return true
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

----------------------------------------------------------------------
-- Names the site keeps (review of #347), and the cut that keeps them whole: here, beside the client's
-- own text rules, so CoreManager and CompanionExport (and every stubbed check that loads them) have
-- them without Utils.
----------------------------------------------------------------------
-- `s` cut to `maxBytes` bytes, never through the middle of a character.
function GuildOS:Utf8Cut(s, maxBytes)
    s = tostring(s or "")
    if #s <= maxBytes then return s end
    local cut = maxBytes
    while cut > 0 and (s:byte(cut + 1) or 0) >= 0x80 and s:byte(cut + 1) < 0xC0 do cut = cut - 1 end
    return s:sub(1, cut)
end

-- Whether `s` is well-formed UTF-8: no stray continuation byte, no character cut short, no overlong
-- form, no surrogate (what the site's decoder would turn into U+FFFD, three bytes longer).
function GuildOS:IsUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local need
        local lo, hi = 0x80, 0xBF
        if c < 0x80 then need = 0
        elseif c >= 0xC2 and c <= 0xDF then need = 1
        elseif c == 0xE0 then need, lo = 2, 0xA0
        elseif c == 0xED then need, hi = 2, 0x9F
        elseif c >= 0xE1 and c <= 0xEF then need = 2
        elseif c == 0xF0 then need, lo = 3, 0x90
        elseif c >= 0xF1 and c <= 0xF3 then need = 3
        elseif c == 0xF4 then need, hi = 3, 0x8F
        else return false end
        for j = 1, need do
            local b = s:byte(i + j)
            if not b or b < (j == 1 and lo or 0x80) or b > (j == 1 and hi or 0xBF) then return false end
        end
        i = i + need + 1
    end
    return true
end

-- The words every object already has as a key on the site (guildos-web lib/core-receipt.ts PROTO_KEYS):
-- a core or a guest named so is refused there.
local PROTO_WORDS = { __proto__ = true, constructor = true, prototype = true }

-- Why `s` cannot be a name the site keeps for a core or a guest (guildos-web lib/core-receipt.ts
-- `isName`): "empty", "long" (over `maxBytes`, 48 by default), "char" (a `|`, a control character or
-- broken UTF-8) or "word" (constructor, prototype, __proto__). nil when it can.
function GuildOS:NameProblem(s, maxBytes)
    if type(s) ~= "string" then return "empty" end
    -- Blank as JavaScript's trim() sees it: ASCII spaces, no-break and the other Unicode spaces.
    local bare = s:gsub("[%s]", ""):gsub("\194\160", ""):gsub("\225\154\128", ""):gsub("\226\128[\128-\138\168\169\175]", "")
        :gsub("\226\129\159", ""):gsub("\227\128\128", ""):gsub("\239\187\191", "")
    if bare == "" then return "empty" end
    if #s > (maxBytes or 48) then return "long" end
    if s:find("[%c|]") or not self:IsUtf8(s) then return "char" end
    if PROTO_WORDS[s] then return "word" end
    return nil
end
