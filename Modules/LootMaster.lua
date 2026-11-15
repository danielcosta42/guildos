----------------------------------------------------------------------
-- Guild OS - Loot Master (Gargul-style)
-- Master Looter announces items, players roll MS/OS, ML awards loot.
-- Integrates with wishlists to show interest on items.
--
-- Since issue #334 the answers are the loot rule's (`LootRule:Responses`), and a raider with GuildOS
-- answers by a button whose answer travels as an addon message: the loot master's client draws the
-- roll, so nobody sends a number of their own and WoW: Forever, which shows no /roll line inside the
-- raid (issue #48), needs none. The messages, all under LootMaster.PREFIX:
--   ASK|sid|<LootRule:Encode>            loot master -> raid, right before ANNOUNCE: the buttons
--   ANNOUNCE|link|seconds|itemId|0or1    loot master -> raid, as always: a client from before reads
--                                        only this one and shows its MS / OS popup, whose /roll lines
--                                        the loot master still reads from chat where chat shows them
--   ANS|sid|KEY|bid|note                 raider -> loot master: over RAID, or whispered when the bid
--                                        is sealed, so that no other client ever holds it
--   ROLL|sid|name|KEY|roll               loot master -> raid: the roll it drew for an answer (the
--                                        raid's chat gets them all in one line when the roll ends)
--   BID|sid|name|KEY|bid                 loot master -> raid: an open bid it took
--   ACK|sid|name|KEY                     loot master -> raid: an answer with nothing else to show
--   NO|sid|name|why|number               loot master -> raid: an answer it refused
--   WON|sid|itemId|KEY|name              loot master who is no officer -> raid, after an award that
--                                        moved a counter: the officers' clients make the same entries
-- Who answered is always the sender the game names, never a name inside the message. Who each message
-- is read from:
--   ASK, ANNOUNCE, ROLL, BID, ACK, NO   the raid's master looter (IsFromMasterLooter), by a raider's client
--   ANS                                 a raid member (the tied, in a roll for a tie), by the master looter's
--   WON                                 the raid's master looter, when no officer, by an officer's client
--   AWARD, UNDO                         as before: an officer of the guild, for what is recorded or forgotten
--
-- Since issue #336 every award keeps a record of why the winner got the item (AwardWhy, LootRule:Why),
-- and a rule whose items a council decides opens a vote when the answers close: its messages (COPEN,
-- CMEM, CCAND, CVOTE, CTALLY, CWHO, CNO, CCLOSE) and its rules are in Modules/LootCouncil.lua.
----------------------------------------------------------------------
-- Not on retail, which is personal loot only (ADR-0026): absent there, as TBC content is elsewhere.
if GuildOS.Client.isRetail then return end

local LootMaster = {}
GuildOS.LootMaster = LootMaster
-- The loot council's addon-message prefix, renamed in #120: a raid on mixed versions
-- must update to hear the master looter.
LootMaster.PREFIX = "GuildOSLM"
local L = GuildOS.L

-- Roll types
LootMaster.ROLL_MS     = "MS"    -- Main Spec
LootMaster.ROLL_OS     = "OS"    -- Off Spec
LootMaster.ROLL_PASS   = "PASS"

-- State
LootMaster.activeLoot        = nil    -- currently announced item
LootMaster.rolls             = {}     -- [playerKey] = { name, class, rollType, roll }
LootMaster.rollTimer         = nil
LootMaster.isMLSession       = false
LootMaster.lootWindowOpen    = false  -- tracks whether loot window is open
LootMaster.listeningForRolls = false  -- true while capturing /roll results from CHAT_MSG_SYSTEM
LootMaster.restrictedRollers = nil    -- set of lowercased names allowed to roll in a tied session; nil = everyone
LootMaster.awardHistory      = {}     -- recent awards for undo
LootMaster.pendingTrades     = {}     -- items awaiting trade: [itemId] = { player, link, itemId, timestamp }
LootMaster.testMode          = false  -- when true, bypasses raid/ML checks for local testing
LootMaster.rollFormat        = nil    -- the localized RANDOM_ROLL_RESULT, set in Initialize()
LootMaster.disenchanter      = ""     -- runtime cache; persisted to GuildOS.db.lootMaster.disenchanter
LootMaster.pendingAsk        = nil    -- a raider's side: the ASK heard, waiting for its ANNOUNCE
LootMaster.heard             = nil    -- a raider's side: { sender, sid, spec, link } of the roll being answered

local ASK_WINDOW = 5          -- seconds an ASK waits for the ANNOUNCE it came with
local NOTE_MAX = 60           -- bytes of a note an answer carries
local ROLL_TOP, ROLL_TOP_SECOND = 100, 99   -- /roll 1-100 is the first answer, /roll 1-99 the second
local ROLLS_LINE_MAX = 200    -- bytes of the line that tells the raid the rolls drawn for it
local ANSWER_BUDGET = 30      -- answers one raider's client may send for one item; the rest are not read
local ANSWER_REPEAT = 5       -- seconds within which the same answer sent again is dropped unanswered

-- Config defaults
LootMaster.ROLL_DURATION = 30     -- seconds to wait for rolls
LootMaster.AUTO_ANNOUNCE = true   -- auto-announce when ML loot window opens
LootMaster.WISHLIST_ONLY_MODE = false  -- only show roll popup to players with item on their wishlist

----------------------------------------------------------------------
-- Safe wrappers: send to raid if in raid, else print locally
----------------------------------------------------------------------
function LootMaster:SafeSendChat(msg, channel)
    if IsInRaid() and not self.testMode then
        SendChatMessage(msg, channel)
    else
        GuildOS:Print("|cff888888[" .. (channel or "CHAT") .. "]|r " .. msg)
    end
end

-- A line sent from an event or a timer, with no click behind it. WoW: Forever drops those
-- (Compat.NeedsClick, #61), so there it prints for the loot master only (issue #63).
function LootMaster:SafeSendChatAuto(msg, channel)
    if GuildOS.Compat.NeedsClick() then
        GuildOS:Print("|cff888888[" .. (channel or "CHAT") .. "]|r " .. msg)
        return
    end
    self:SafeSendChat(msg, channel)
end

function LootMaster:SafeSendAddon(prefix, payload, channel)
    if IsInRaid() and not self.testMode then
        GuildOS.Compat.SendAddonMessageNow(prefix, payload, channel)
    end
end

----------------------------------------------------------------------
-- Per-core config helpers.
-- All reads go through GetCfg() so they automatically reflect the
-- active core's overrides; all writes go through SaveCfgKey() so they
-- are persisted in the right place.
----------------------------------------------------------------------
function LootMaster:GetCfg()
    if GuildOS.CoreManager then
        return GuildOS.CoreManager:GetLootConfig()
    end
    return GuildOS.db.lootMaster or {}
end

-- Caches the active core's values (read via GetCfg so cores are respected from the start); run
-- again whenever the active core changes (issue #99).
function LootMaster:LoadCfg()
    local cfg = self:GetCfg()
    self.ROLL_DURATION      = cfg.rollDuration or 30
    self.AUTO_ANNOUNCE      = cfg.autoAnnounce
    self.WISHLIST_ONLY_MODE = cfg.wishlistOnlyMode or false
    self.disenchanter       = cfg.disenchanter or ""
    self.LOOT_THRESHOLD     = cfg.lootThreshold or 3
end

function LootMaster:SaveCfgKey(key, value)
    if GuildOS.CoreManager then
        GuildOS.CoreManager:SetLootConfigKey(key, value)
    elseif GuildOS.db.lootMaster then
        GuildOS.db.lootMaster[key] = value
    end
end

-- One loot setting of a core ("" the guild's own), from the Loot window's Rule tab (issue #346): the
-- one place it is edited. The same keys as always, checked as the screens of before checked them: a
-- roll lasts 5 to 120 seconds, attendance is a percentage, the bids' least and time are whole, the
-- threshold is a quality from uncommon to legendary, the switches are yes or no and the names are
-- trimmed. The active core's figures the loot master caches are read again. Returns the value kept,
-- or nil and why ("range" for a figure out of bounds, "key" for a setting that is none).
local SETTING_SWITCHES = { autoAnnounce = true, wishlistOnlyMode = true, attTiebreaker = true, recvPenalty = true }
local SETTING_NAMES = { disenchanter = true, bank = true }
function LootMaster:SetLootSetting(key, value, scope)
    if SETTING_SWITCHES[key] then
        value = value and true or false
    elseif SETTING_NAMES[key] then
        value = strtrim(tostring(value or ""))
    elseif key == "rollDuration" then
        value = tonumber(value)
        if not value or value < 5 or value > 120 then return nil, "range" end
        value = math.floor(value)
    elseif key == "minAttendancePct" then
        value = math.max(0, math.min(100, math.floor(tonumber(value) or 0)))
    elseif key == "dkpMinBid" then
        value = math.max(0, math.floor(tonumber(value) or 0))
    elseif key == "dkpBidTime" then
        value = math.max(5, math.floor(tonumber(value) or 30))
    elseif key == "lootThreshold" then
        value = tonumber(value)
        if not value or value < 2 or value > 5 then return nil, "range" end
    else
        return nil, "key"
    end
    if GuildOS.CoreManager then
        GuildOS.CoreManager:SetLootConfigKey(key, value, scope or "")
    elseif GuildOS.db.lootMaster then
        GuildOS.db.lootMaster[key] = value
    end
    self:LoadCfg()
    return value
end

-- The loot settings of a core ("" the guild's), as the Rule tab shows them.
function LootMaster:LootSettings(scope)
    if GuildOS.CoreManager then return GuildOS.CoreManager:GetLootConfig(scope or "") end
    return GuildOS.db.lootMaster or {}
end

-- How long a roll stays open: the loot rule's own time when it names one (issue #334), else the
-- roll duration of the loot settings.
function LootMaster:RollTime()
    return self:Rule().time or self.ROLL_DURATION or 30
end

-- The rule and the loot system of the item being rolled for. An item keeps the ones it was announced
-- under (issue #338): another core becoming the raid's, or an officer saving another rule, changes the
-- next item and never the roll in progress. With no roll open, the ones in force.
function LootMaster:Rule()
    local loot = self.activeLoot
    return (loot and loot.rule) or GuildOS.LootRule:Active()
end

function LootMaster:System()
    local loot = self.activeLoot
    return (loot and loot.system) or (GuildOS.GetLootSystem and GuildOS:GetLootSystem()) or "rolls"
end

-- The core whose points, counters, queues and award log an item belongs to: the raid's when the item
-- was announced, kept on it like its rule (issue #338). The raid's core changing while a roll is open
-- used to send the charge, the +1 and the award log to the new core, with the rule and the balances
-- the order was read from still the old one's.
function LootMaster:ActiveCore()
    return GuildOS.CoreManager and GuildOS.CoreManager:GetActiveName() or ""
end

-- Runs `fn(...)` on the accounts of the item being given (Points:InCore). With no item, or one that
-- names no core, on the active core's.
function LootMaster:InLootCore(fn, ...)
    local P, loot = GuildOS.Points, self.activeLoot
    if not (P and P.InCore and loot and loot.core ~= nil) then return fn(...) end
    return P:InCore(loot.core, fn, ...)
end

----------------------------------------------------------------------
-- Whether the Loot Master module is currently enabled.
-- Read live from settings so the Settings toggle takes effect at runtime
-- (no /reload): the event handlers and hooks consult this on every fire.
----------------------------------------------------------------------
function LootMaster:IsModuleEnabled()
    -- The guild's loot system can switch the whole module off ("external"):
    -- guilds distributing loot with Gargul/RCLootCouncil want zero GuildOS
    -- loot behaviour (no popups, rolls, council, or history).
    if GuildOS.LootSystemActive and not GuildOS:LootSystemActive() then
        return false
    end
    local m = GuildOS.db and GuildOS.db.settings and GuildOS.db.settings.modules
    return not m or m.lootMaster ~= false
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function LootMaster:Initialize()
    if not GuildOS.db.lootMaster then
        GuildOS.db.lootMaster = {
            rollDuration = 30,
            autoAnnounce = true,
            wishlistOnlyMode = false,
            awardHistory = {},
        }
    end

    -- Ensure loot-distribution settings exist in the global fallback (added in v2)
    local lmdb = GuildOS.db.lootMaster
    if lmdb.minAttendancePct == nil then lmdb.minAttendancePct = 0    end
    if lmdb.attTiebreaker    == nil then lmdb.attTiebreaker    = true end
    if lmdb.recvPenalty      == nil then lmdb.recvPenalty      = true end
    if lmdb.awardHistory     == nil then lmdb.awardHistory     = {}   end
    if lmdb.disenchanter     == nil then lmdb.disenchanter     = ""   end
    if lmdb.lootThreshold    == nil then lmdb.lootThreshold    = 3    end

    self:LoadCfg()
    self.pendingTrades      = {}

    -- /roll lines are read through the localized RANDOM_ROLL_RESULT ("%s rolls %d (%d-%d)." in
    -- English), by GuildOS:MatchFormat: a language that numbers its arguments ("%1$s ... %2$d")
    -- read nothing before, without a word (#160).
    self.rollFormat = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)."

    local frame = CreateFrame("Frame")
    GuildOS.Compat.RegisterEvent(frame, "LOOT_OPENED")
    GuildOS.Compat.RegisterEvent(frame, "LOOT_CLOSED")
    GuildOS.Compat.RegisterEvent(frame, "CHAT_MSG_ADDON")
    GuildOS.Compat.RegisterEvent(frame, "CHAT_MSG_SYSTEM")  -- capture /roll results
    GuildOS.Compat.RegisterEvent(frame, "TRADE_SHOW")
    GuildOS.Compat.RegisterEvent(frame, "TRADE_ACCEPT_UPDATE")
    -- GROUP_LEFT: disenchanter is now persisted to DB, no need to clear
    -- START_LOOT_ROLL intentionally NOT registered: it only fires under native
    -- Group Loot (need/greed/pass), where there is no GuildOS master looter
    -- collecting rolls. Popping the MS/OS roll frame there just duplicates
    -- Blizzard's window with meaningless /roll buttons. The raid MS/OS popup is
    -- driven by the ANNOUNCE addon message instead (see OnAddonMessage).
    frame:SetScript("OnEvent", function(_, event, ...)
        -- Runtime kill-switch: when the module is toggled off in Settings,
        -- ignore all loot events immediately (no /reload needed).
        if not LootMaster:IsModuleEnabled() then return end
        if event == "LOOT_OPENED" then
            LootMaster:OnLootOpened()
        elseif event == "LOOT_CLOSED" then
            LootMaster:OnLootClosed()
        elseif event == "CHAT_MSG_ADDON" then
            LootMaster:OnAddonMessage(...)
        elseif event == "CHAT_MSG_SYSTEM" then
            LootMaster:OnSystemMessage(...)
        elseif event == "TRADE_SHOW" then
            LootMaster:OnTradeShow()
        elseif event == "TRADE_ACCEPT_UPDATE" then
            LootMaster:OnTradeAcceptUpdate(...)
        end
    end)

    GuildOS.Compat.RegisterAddonPrefix(LootMaster.PREFIX)
    self.eventFrame = frame

    self:HookBagClicks()
end

----------------------------------------------------------------------
-- Alt+Click on any bag item starts a GuildOS roll for that item (ML only).
-- Uses the trade-delivery path since there is no ML loot window for bag items.
----------------------------------------------------------------------
function LootMaster:RollFromBagClick(bagId, slotId)
    if not LootMaster:IsModuleEnabled() then return end
    if not IsAltKeyDown() then return end
    if not LootMaster:IsMasterLooter() then return end
    LootMaster:RollFromBag(bagId, slotId)
end

-- Anniversary's bags call ContainerFrameItemButton_OnModifiedClick(button). WoW: Forever's
-- are the retail container, with no such global: they call HandleModifiedItemClick(link,
-- itemLocation), the bag and slot inside the location (issue #44). One hook, never both,
-- so a click never starts two rolls. A chat link has no location and starts nothing.
function LootMaster:HookBagClicks()
    if ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn)
            LootMaster:RollFromBagClick(btn:GetParent():GetID(), btn:GetID())
        end)
    elseif HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(_, itemLocation)
            if not (itemLocation and itemLocation.IsBagAndSlot and itemLocation:IsBagAndSlot()) then return end
            local bagId, slotId = itemLocation:GetBagAndSlot()
            -- The player's own bags: backpack 0, four bags, the reagent bag. The bank's are
            -- bag-and-slot too, and the trade path cannot hand over what is in the bank.
            if bagId and bagId >= 0 and bagId <= 5 then LootMaster:RollFromBagClick(bagId, slotId) end
        end)
    end
end

----------------------------------------------------------------------
-- Apply a Settings module toggle at runtime (no /reload).
-- Enabling for the first time (module was off at login, so Initialize
-- never ran) does a lazy Initialize; the caller has already written
-- db.settings.modules.lootMaster, which IsModuleEnabled() reads live.
-- Disabling hides any open loot frames; the OnEvent gate stops new ones.
----------------------------------------------------------------------
function LootMaster:SetEnabled(enabled)
    if enabled then
        if not self.eventFrame then
            self:Initialize()
        end
    else
        if self.lootFrame    then self.lootFrame:Hide()    end
        if self.rollFrame    then self.rollFrame:Hide()    end
        if self.rollPopup    then self.rollPopup:Hide()    end
        if self.councilFrame then self.councilFrame:Hide() end
    end
end

----------------------------------------------------------------------
-- Returns { att25, recvThisLockout } for a player — used for roll
-- gating, sort tiebreakers, and UI column display.
----------------------------------------------------------------------
function LootMaster:GetPlayerContext(playerName)
    local ctx = { att25 = 0, recvThisLockout = 0 }
    if not playerName then return ctx end

    -- 25-man attendance %, the raid's own core's (issue #134): its loot rules are that core's, and a
    -- raider on several cores (#132) is judged by the one raiding, not by where they raid most. With
    -- no core active, or one none of whose nights count (a 10 on Forever, a core on its first raid,
    -- where everyone would read 0% and roll OS), the roster's figure: the core where the raider has the
    -- most nights that count.
    local RT = GuildOS.RaidTracker
    if RT then
        local pKey = GuildOS:GetPlayerKey(playerName, GetRealmName())
        local core = (self.activeLoot and self.activeLoot.core) or (RT.GetCurrentGroup and RT:GetCurrentGroup())
        if core == "" or (core and RT:GetTotal25ManSessions(core) == 0) then core = nil end
        ctx.att25 = RT:GetAttendance25ManPercent(pKey, core) or 0
    end

    -- Items received this lockout: count ML-awarded loot history entries
    -- from the current raid session start (or last 8 hours as fallback).
    if GuildOS.db and GuildOS.db.lootHistory then
        local sessionStart = 0
        if GuildOS.RaidTracker and GuildOS.RaidTracker.currentRaid then
            sessionStart = GuildOS.RaidTracker.currentRaid.startTime or 0
        end
        if sessionStart == 0 then
            sessionStart = GetServerTime() - (8 * 3600)
        end
        local pKey   = GuildOS:GetPlayerKey(playerName)
        for _, entry in ipairs(GuildOS.db.lootHistory) do
            if entry.fromML
                and entry.playerKey == pKey
                and (entry.timestamp or 0) >= sessionStart
            then
                ctx.recvThisLockout = ctx.recvThisLockout + 1
            end
        end
    end

    return ctx
end

----------------------------------------------------------------------
-- Check if the local player is the designated Master Looter.
--
-- Rules (mirrors Gargul's approach):
--   1. Must be in a group (party or raid) — never true when solo.
--   2. Loot method must be "master" AND this player must be the ML.
--
-- The native IsMasterLooter() already encodes both conditions:
--   it returns true only when in a group, loot is set to master, and
--   this player is the chosen looter.  All fallbacks must obey the
--   same contract; none return true for a solo player or a leader
--   whose group uses any other loot method.
----------------------------------------------------------------------
function LootMaster:IsMasterLooter()
    -- Test mode: bypass all checks for solo testing
    if self.testMode then return true end

    -- Must be in a group — never activate in open world
    if not IsInGroup() then return false end

    -- 1. Native WoW API (most reliable; works on TBC Anniversary)
    if IsMasterLooter and IsMasterLooter() then
        return true
    end

    -- 2. GetLootMethod fallback (Classic/TBC):
    --    partyID == 0  → local player is the master looter in a party
    --    masterLooterRaidID == local raid index → player is ML in a raid
    if GetLootMethod then
        local method, masterLootPartyID, masterLooterRaidID = GetLootMethod()
        if method == "master" then
            -- Party case: partyID 0 means this player
            if masterLootPartyID == 0 then return true end
            -- Raid case: compare against local player's raid index
            if masterLooterRaidID and IsInRaid() then
                if GuildOS.Compat.IsPlayer("raid" .. masterLooterRaidID) then return true end
            end
        end
    end

    -- 3. C_PartyInfo, the only one WoW: Forever has. It answers method, party index,
    --    raid index — the second is the party's, and reading it as the raid's never
    --    recognised the master looter there (issue #44).
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local method, partyID, raidID = C_PartyInfo.GetLootMethod()
        local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
        if method == master then
            if partyID == 0 then return true end
            if raidID and IsInRaid() and GuildOS.Compat.IsPlayer("raid" .. raidID) then return true end
        end
    end

    return false
end

----------------------------------------------------------------------
-- Who may open a roll, as a raider's client reads it. Everything a master looter's client tells the
-- raid (ASK, ANNOUNCE, ROLL, BID, ACK, NO and the council's COPEN, CMEM, CCAND, CTALLY, CWHO, CNO,
-- CCLOSE) is read from the raid's master looter and from nobody else: a raider who replayed an ASK
-- used to have every answer, sealed bids among them, sent to them in place of the master looter.
--
-- The game says who the master looter is by their place in the raid. Where it names none (group loot,
-- or a client with no master loot to ask about) the raid's leader and its assistants stand in: they
-- are who the raid already trusts with its marks and invites, and nobody else is read.
----------------------------------------------------------------------
-- The master looter's place in the raid, or nil when the game names none.
function LootMaster:MasterLooterIndex()
    local raidID
    if GetLootMethod then
        local method, _, id = GetLootMethod()
        if method == "master" then raidID = id end
    end
    if not raidID and C_PartyInfo and C_PartyInfo.GetLootMethod then
        local method, _, id = C_PartyInfo.GetLootMethod()
        local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
        if method == master then raidID = id end
    end
    if not (raidID and IsInRaid()) then return nil end
    return raidID
end

function LootMaster:MasterLooterName()
    local raidID = self:MasterLooterIndex()
    if not raidID then return nil end
    return (GuildOS.Compat.UnitIdentity("raid" .. raidID))
end

-- The place in the raid of `sender`, as the game names an addon message's or a /roll line's, or nil
-- for somebody outside it. The whole name decides. On a client with surnames one side may hold the
-- first name alone (issue #48): it then decides only when a single raider has that first name, so two
-- raiders who share one are never taken for each other.
function LootMaster:SenderRaidIndex(sender)
    if GuildOS.Compat.IsSecret(sender) or type(sender) ~= "string" or sender == "" then return nil end
    local name = sender:match("^([^%-]+)") or sender
    local loose, matches = nil, 0
    for i = 1, GetNumGroupMembers() or 0 do
        local uName, uSecond = GuildOS.Compat.UnitIdentity("raid" .. i)
        if uName then
            local surnamed = GuildOS.Client.has.surnames and uSecond and uSecond ~= ""
            local whole = surnamed and (uName .. " " .. uSecond) or uName
            if whole == name or whole == sender then return i end
            -- Named by the first name alone, whichever way the game hands the surname (apart, or
            -- inside the name): counted, never taken at once, or the first "Ana" of the raid would
            -- answer for every other one.
            if GuildOS.Client.has.surnames and self:WholeRollerName(name, uName, uSecond) then
                loose, matches = i, matches + 1
            end
        end
    end
    return matches == 1 and loose or nil
end

-- Whether `sender` is who this raid's rolls and votes are read from: its master looter, and nobody
-- else. Where the game names none nobody is: this module only ever announces under master loot
-- (IsMasterLooter), so a roll or a vote opened without one comes from no honest client, and reading it
-- from the leader or an assistant would hand them every sealed bid and the council's votes.
function LootMaster:IsFromMasterLooter(sender)
    local index = self:SenderRaidIndex(sender)
    local ml = self:MasterLooterIndex()
    return index ~= nil and ml ~= nil and index == ml
end

----------------------------------------------------------------------
-- /roll capture: start/stop listening for CHAT_MSG_SYSTEM roll results
----------------------------------------------------------------------
function LootMaster:StartListeningForRolls()
    self.listeningForRolls = true
    self.saidHidden = nil
end

function LootMaster:StopListeningForRolls()
    self.listeningForRolls = false
end

-- Called on every CHAT_MSG_SYSTEM event
function LootMaster:OnSystemMessage(message)
    -- In lockdown a roll's line cannot be read, so it is not counted: the roll is missed, not misread.
    -- Whoever runs the roll is told, once, or it looks as if nobody rolled (issue #48).
    if GuildOS.Compat.IsSecret(message) then
        if self.listeningForRolls and self.activeLoot and not self.saidHidden then
            self.saidHidden = true
            GuildOS:Print(L["|cffFFAA00[Loot] The game is hiding chat right now, so rolls are not being read.|r"])
        end
        return
    end
    if not self.listeningForRolls or not self.activeLoot then return end
    self:ProcessSystemRoll(message)
end

----------------------------------------------------------------------
-- WoW: Forever: the whole name when a /roll line and a raid unit are the same person, else nil.
-- Neither has been seen in a raid: the line may or may not carry the surname, and UnitName may
-- give it joined, in its second slot or not at all (issue #48). With the surname on one side
-- only, the first name decides: a stranger nearby who shares it could roll, and two raiders who
-- share it read as the first one, but a raider's roll going unread is worse.
----------------------------------------------------------------------
function LootMaster:WholeRollerName(roller, name, surname)
    local whole = (surname and surname ~= "") and (name .. " " .. surname) or name
    if whole == roller then return whole end
    if whole:find(" ", 1, true) and roller:find(" ", 1, true) then return nil end
    if whole:match("^%S+") ~= roller:match("^%S+") then return nil end
    return #whole > #roller and whole or roller
end

----------------------------------------------------------------------
-- Parse a CHAT_MSG_SYSTEM /roll line and register it as MS or OS.
--   MS = RandomRoll(1, 100)  |  OS = RandomRoll(1, 99)
-- All other roll ranges are ignored.
----------------------------------------------------------------------
function LootMaster:ProcessSystemRoll(message)
    local args = GuildOS:MatchFormat(message, self.rollFormat)
    if not args or not args[1] then return end
    local roller, roll, low, high = args[1], args[2], args[3], args[4]

    roll = tonumber(roll)
    low  = tonumber(low)
    high = tonumber(high)
    if not roll or not low or not high then return end

    -- Only the two agreed-upon ranges count; ignore all other /roll usage. They are the rule's first
    -- and second answers (MS and OS unless the guild named others, issue #334), and only when that
    -- answer asks for a roll: a bid, or an answer with no roll, has no /roll line.
    local list = GuildOS.LootRule:Responses(self:Rule())
    local response
    if low == 1 and high == ROLL_TOP then
        response = list[1]
    elseif low == 1 and high == ROLL_TOP_SECOND then
        response = list[2]
    end
    if not response or (response.ask or "roll") ~= "roll" then return end

    local cleanName = self:RaidRollerName(roller)
    if not cleanName then return end

    -- Restricted-roll session: only allowed players may roll; ignore everyone else silently
    if self.restrictedRollers and not self.restrictedRollers[strlower(cleanName)] then
        return
    end

    -- An open bid stands (TakeAnswerNow): a /roll for another answer does not take it back either.
    local held = self.rolls[GuildOS:GetPlayerKey(cleanName)]
    if held and held.bid and held.rollType ~= "PASS" and response.key ~= held.rollType
        and GuildOS.LootRule:HasBids(self:Rule()) and not GuildOS.LootRule:BidRules(self:Rule()) then
        return
    end

    -- One roll a player and an item: the first one read or drawn stands. A /roll after it changes the
    -- answer, never the number.
    local kept = self:KeepRoll(cleanName, roll, false)
    self:RegisterRoll(cleanName, response.key, kept.roll, { drawn = kept.drawn or nil })
end

----------------------------------------------------------------------
-- The one roll `name` has for the item being rolled for. The first number read from a /roll line or
-- drawn here for a button is kept apart from the row, which every new answer rewrites: a pass, a bid or
-- an answer that asks for no roll in between never buys another draw. `roll` is the number to keep
-- when the player has none yet (nil: only look), `drawn` whether this client drew it.
-- Returns { roll, drawn }, or nil.
----------------------------------------------------------------------
function LootMaster:KeepRoll(name, roll, drawn)
    local loot = self.activeLoot
    if not loot then return nil end
    loot.kept = loot.kept or {}
    local key = GuildOS:GetPlayerKey(name)
    if not loot.kept[key] and roll then loot.kept[key] = { roll = roll, drawn = drawn and true or false } end
    return loot.kept[key]
end

----------------------------------------------------------------------
-- The name a roller or the sender of an answer has in this raid, or nil for somebody outside it: only
-- a raid member's roll or answer counts. `roller` is the name of a /roll line or of an addon
-- message's sender, with or without its realm.
----------------------------------------------------------------------
function LootMaster:RaidRollerName(roller)
    if GuildOS.Compat.IsSecret(roller) or type(roller) ~= "string" or roller == "" then return nil end
    -- Strip realm suffix that may appear in some client versions
    local cleanName = roller:match("^([^%-]+)") or roller
    if self.testMode then return cleanName end
    local numMembers = GetNumGroupMembers() or 0
    for i = 1, numMembers do
        local uName, uSecond = GuildOS.Compat.UnitIdentity("raid" .. i)
        local whole = uName and GuildOS.Client.has.surnames
            and self:WholeRollerName(cleanName, uName, uSecond)
        if whole then return whole end
        if uName and (uName == cleanName or uName == roller) then return cleanName end
    end
    -- Also accept own roll (solo / testMode outside raid)
    if cleanName == GuildOS.Compat.PlayerName() then return cleanName end
    return nil
end

----------------------------------------------------------------------
-- Loot window events
----------------------------------------------------------------------
function LootMaster:OnLootOpened()
    -- ML distribution only works in a group (party or raid).
    -- Never activate in open world (solo).
    if not IsInGroup() and not self.testMode then return end
    if not self:IsMasterLooter() then return end

    self.isMLSession = true
    self.lootWindowOpen = true

    -- Respect the "Auto-announce loot when ML opens loot window" toggle.
    -- When off, do not auto-open the master-loot screen; the ML uses normal
    -- looting. Re-enabling the toggle brings the screen back. Read live via
    -- GetCfg() so the active core's setting (and CorePanel edits) apply.
    if self:GetCfg().autoAnnounce == false then return end

    -- Collect Rare+ and BoE items (BoE regardless of quality)
    local numItems = GetNumLootItems()
    local items = {}
    for i = 1, numItems do
        local _, itemName, _, _, quality = GetLootSlotInfo(i)  -- BCC Anniversary: icon, name, count, currencyID, quality, locked, ...
        local link = GetLootSlotLink(i)
        if link then
            local q = quality or 1
            local meetsThreshold = q >= (self.LOOT_THRESHOLD or 3)
            local isBoE = false
            local itemId = tonumber(link:match("item:(%d+)"))
            if itemId then
                local bindType = select(14, GuildOS.Compat.GetItemInfo(itemId))
                isBoE = bindType == 2
            end
            if meetsThreshold or isBoE then
                table.insert(items, {
                    slot    = i,
                    link    = link,
                    name    = itemName,
                    quality = q,
                })
            end
        end
    end

    if #items > 0 then
        GuildOS.LootMaster:ShowLootFrame(items)
    end
end

function LootMaster:OnLootClosed()
    self.isMLSession = false
    self.lootWindowOpen = false

    -- If there is a pending loot session (roll in progress or ended but not yet
    -- awarded), warn the ML and keep activeLoot intact so Award/DE still work
    -- via the trade path (lootWindowOpen=false → QueueForTrade).
    if self.activeLoot and not self.activeLoot.delivered then
        GuildOS:Print("|cffFF9900[LootMaster]|r " .. L["Loot window closed before delivery - use the roll frame to deliver the item via trade."])
    end
end

----------------------------------------------------------------------
-- Check if current player has itemId on their native wishlist.
-- Reads from the per-char wishlists table (GuildOS.db.wishlists[charKey]),
-- NOT from the legacy flat myWishlist key which is nil'd out on migration.
----------------------------------------------------------------------
function LootMaster:PlayerHasItemOnWishlist(itemId)
    if not GuildOS.Wishlist then return false end
    local list = GuildOS.Wishlist:GetMyList()
    for _, entry in ipairs(list) do
        if entry.itemId == itemId then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Resolve wishlist council for an item: returns sorted list of interested
-- raiders currently in raid, or nil if no wishlist data.
-- Each entry: { name, class, type ("wishlist"), order }
----------------------------------------------------------------------
function LootMaster:ResolveWishlistCouncil(itemId)
    if not GuildOS.Wishlist or not itemId or itemId == 0 then return nil end

    local interest = GuildOS.Wishlist:GetItemInterest(itemId)
    if not interest or #interest == 0 then return nil end

    -- Build set of players currently in raid
    local inRaid = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local name, _, classFile = GuildOS.Compat.UnitIdentity("raid" .. i)
        if name then
            inRaid[strlower(name)] = classFile or "UNKNOWN"
        end
    end
    -- In testMode, treat the current player as in raid so council logic is testable
    if self.testMode then
        local myName = GuildOS.Compat.PlayerName()
        if myName then
            inRaid[strlower(myName)] = select(2, UnitClass("player")) or "UNKNOWN"
        end
    end

    -- Filter to only raiders present
    local candidates = {}
    for _, entry in ipairs(interest) do
        if inRaid[strlower(entry.name)] then
            table.insert(candidates, {
                name        = entry.name,
                class       = inRaid[strlower(entry.name)],
                wishlistType = "wishlist",
                order       = entry.order or 999,
            })
        end
    end

    return (#candidates > 0) and candidates or nil
end

----------------------------------------------------------------------
-- Resolve officer prio list for an item: returns ordered list of entries
-- currently in raid, in prio order. Returns nil if no prio data.
----------------------------------------------------------------------
function LootMaster:ResolvePrioList(itemId)
    if not GuildOS.db or not GuildOS.db.lootPrios then return nil end
    local prioList = GuildOS.db.lootPrios[itemId]
    if not prioList or #prioList == 0 then return nil end

    -- Build set of players currently in raid
    local inRaid = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local name = GuildOS.Compat.UnitIdentity("raid" .. i)
        if name then inRaid[strlower(name)] = true end
    end
    if self.testMode then
        local myName = GuildOS.Compat.PlayerName()
        if myName then inRaid[strlower(myName)] = true end
    end

    -- Return only prio entries for raiders present, in order
    local result = {}
    for _, entry in ipairs(prioList) do
        if inRaid[strlower(entry.name or "")] then
            table.insert(result, entry)
        end
    end
    return #result > 0 and result or nil
end

----------------------------------------------------------------------
-- The roll's timers. Each one is its roll's alone: it is cancelled when the roll ends, is cancelled,
-- is awarded or gives way to another item, and its closure checks the roll it was started for, so one
-- that fires late never ends, or counts down, the item that came after.
----------------------------------------------------------------------
function LootMaster:StartRollTimer(duration)
    if self.rollTimer then self.rollTimer:Cancel() end
    local sid = self.activeLoot and self.activeLoot.sid
    self.rollTimer = C_Timer.NewTimer(duration, function()
        local loot = LootMaster.activeLoot
        if loot and loot.sid == sid and not loot.ended then LootMaster:EndRolling() end
    end)
end

function LootMaster:StopRollTimer()
    if self.rollTimer then
        self.rollTimer:Cancel()
        self.rollTimer = nil
    end
end

-- The roll in progress gives way, with no line to the raid: no timer of it, no /roll line and no
-- council's vote outlives it.
function LootMaster:DropRoll()
    self:StopListeningForRolls()
    self:StopRollTimer()
    local loot = self.activeLoot
    if loot and loot.council and loot.council.open and GuildOS.LootCouncil then
        GuildOS.LootCouncil:Close("cancel")
    end
end

-- The item whose roll is open now (answers still being taken, or its council voting), or nil: the
-- loot window opens no other roll over it.
function LootMaster:OpenRoll()
    local loot = self.activeLoot
    if not loot or loot.delivered then return nil end
    if loot.council and loot.council.open then return loot.link or "?" end
    if loot.sid and not loot.ended and (self.rollTimer or self.listeningForRolls) then return loot.link or "?" end
    return nil
end

----------------------------------------------------------------------
-- Announce an item for rolling.
-- Priority logic (always active, regardless of WISHLIST_ONLY_MODE):
--   ≥ 2 players tied at top wishlist position in raid → restricted roll (only they roll)
--   1 clear winner + WISHLIST_ONLY_MODE          → AutoCouncilAward (direct award prompt)
--   otherwise                                 → open MS/OS roll for all
----------------------------------------------------------------------
function LootMaster:AnnounceItem(itemLink, lootSlot)
    if not IsInRaid() and not self.testMode then
        GuildOS:Print(L["You must be in a raid to announce loot."])
        return
    end

    -- The item before is over, whatever state it was left in: its timer (which used to run out on the
    -- next item and, with nobody asking for that one yet, send it to the disenchanter), its /roll
    -- lines, and its council's vote, whose windows the raiders' clients close on hearing so.
    self:DropRoll()

    -- Clear previous session
    self.rolls             = {}
    self.restrictedRollers = nil
    -- The rule and the loot system in force now are this item's until it is given (issue #338).
    self.activeLoot = nil
    local rule = GuildOS.LootRule:Active()
    local system = (GuildOS.GetLootSystem and GuildOS:GetLootSystem()) or "rolls"
    self.activeLoot = {
        link      = itemLink,
        slot      = lootSlot,
        startTime = GetServerTime(),
        endTime   = GetServerTime() + (rule.time or self.ROLL_DURATION or 30),
        sid       = self:NewSessionId(),
        rule      = rule,
        system    = system,
        core      = self:ActiveCore(),          -- whose accounts and award log this item is given in
        ruleAt    = GuildOS.LootRule:Stamp(),   -- for the award's record (issue #336)
    }

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    self.activeLoot.itemId = itemId

    -- The guild's chosen loot system (Settings) decides the default flow:
    -- "wishlist"/"tmb" force wishlist auto-council; "dkp"/"rolls" open a roll
    -- (DKP just changes how the roll frame ranks and what award charges).
    -- An item that follows another rule (issue #335): a fixed destination has no roll at all, and an
    -- exception that swaps blocks is the rule this item is announced and decided by.
    local item = self:ItemFacts(itemLink, lootSlot)
    local played, exception = GuildOS.LootRule:ForItem(rule, item)
    self.activeLoot.item, self.activeLoot.baseRule = item, rule
    -- An item the client has not read yet (GetItemInfo answers nothing until the server does) has no
    -- quality, class or binding to tell its category by. A rule with an exception for a category then
    -- cannot say whether this item is one: it is played by the general rule, and both the loot master
    -- and the raid are told so. Never guessed: an item is not sent to the bank on a maybe.
    if not exception and item.quality == nil and GuildOS.LootRule:NeedsItemInfo(rule) then
        self.activeLoot.unread = true
        GuildOS:Print("|cffFFAA00" .. itemLink .. L["  -  item details not loaded yet: the general rule applies"] .. "|r")
    end
    if exception and exception.to then
        self:SendToDestination(exception, itemLink, lootSlot, itemId)
        return
    end
    -- A rule that keeps a queue (Suicide Kings, issue #337): whoever of the raid it never saw joins it
    -- before anybody answers, so every place is known when the answers come.
    self:JoinQueues(played)
    if exception then
        self.activeLoot.rule, self.activeLoot.exception = played, exception
        self.activeLoot.endTime = GetServerTime() + (played.time or self.ROLL_DURATION or 30)
        self:DoNormalAnnounce(itemLink, lootSlot, itemId, nil, nil)
        return
    end

    -- The raid night's own rule (the site's, guildos-web#516) says the whole order: it opens its roll
    -- for everyone, with none of the shortcuts the loot systems of before take by the wishlist.
    if GuildOS.LootRule.Night and GuildOS.LootRule:Night() == rule then
        self.activeLoot.night = true
        self:DoNormalAnnounce(itemLink, lootSlot, itemId, nil, nil)
        return
    end
    -- So does a rule with a council, a queue, a bonus account or a summed score (issues #336, #337):
    -- every candidate is read, so nobody is left out of the roll by a place on the wishlist.
    if GuildOS.LootRule:PlaysWhole(rule) then
        self:DoNormalAnnounce(itemLink, lootSlot, itemId, nil, nil)
        return
    end

    local lootSystem = system
    local wishlistOnly = self.WISHLIST_ONLY_MODE or lootSystem == "wishlist" or lootSystem == "tmb"

    -- Check officer prios first — they override wishlist council
    if itemId and itemId > 0 then
        local prioList = self:ResolvePrioList(itemId)
        if prioList then
            local topPrio = prioList[1]
            if wishlistOnly then
                -- Direct award prompt for top prio player
                local council = self:ResolveWishlistCouncil(itemId) or {}
                self:AnnounceSoftReserves(itemId)
                self:AutoCouncilAward(
                    { name = topPrio.name, class = topPrio.class or "UNKNOWN", order = 1, isPrio = true },
                    itemLink, lootSlot, council)
            else
                -- Open roll but announce prio info (DoNormalAnnounce calls AnnounceSoftReserves)
                self:DoNormalAnnounce(itemLink, lootSlot, itemId, nil, topPrio)
            end
            return
        end
    end

    -- No officer prio — check wishlist interest for tied top entries currently in raid
    if itemId and itemId > 0 then
        local council = self:ResolveWishlistCouncil(itemId)
        if council then
            local top  = council[1]
            local tied = {}
            for _, c in ipairs(council) do
                if c.order == top.order then
                    table.insert(tied, c)
                end
            end

            if #tied >= 2 then
                -- Tie at top of wishlist: only those players roll
                self:StartRestrictedRoll(tied, council, itemLink, lootSlot, itemId)
                return
            elseif #tied == 1 and wishlistOnly then
                -- Single top entry + wishlist-only mode: prompt ML for direct award
                self:AnnounceSoftReserves(itemId)
                self:AutoCouncilAward(top, itemLink, lootSlot, council)
                return
            end
            -- Single top entry but WISHLIST_ONLY_MODE off: open roll, mention winner
            self:DoNormalAnnounce(itemLink, lootSlot, itemId, top, nil)
            return
        end
    end

    -- No wishlist data for this item: open roll for all
    self:DoNormalAnnounce(itemLink, lootSlot, itemId, nil, nil)
end

----------------------------------------------------------------------
-- Normal announce — open MS/OS roll for everyone in the raid.
-- topEntry (optional): wishlist entry of the single top player.
-- prioEntry (optional): officer prio entry of the top prio player.
-- One of these is used to post an info line about who has priority.
----------------------------------------------------------------------
function LootMaster:DoNormalAnnounce(itemLink, _lootSlot, itemId, topEntry, prioEntry)
    local duration = self:RollTime()
    -- Main announce (DKP mode rolls register interest; the ML awards by standings)
    local announceLine = self:AnnounceLine(itemLink, duration)
    -- An item that follows an exception says which one (issue #335).
    local exception = self.activeLoot and self.activeLoot.exception
    if exception then
        announceLine = announceLine .. string.format(L["  -  exception: %s"], GuildOS.LootRule:ExceptionLabel(exception))
    end
    if self.activeLoot and self.activeLoot.unread then
        announceLine = announceLine .. L["  -  item details not loaded yet: the general rule applies"]
    end
    self:SafeSendChat(announceLine, "RAID_WARNING")

    -- Post priority info note
    if prioEntry then
        local infoMsg = format(L["[Priority] %s has official prio #1 - roll open to everyone"],
            prioEntry.name)
        self:SafeSendChat(infoMsg, "RAID")
    elseif topEntry then
        local infoMsg = format(L["[Priority] %s (#%d on wishlist) - roll open to everyone"],
            topEntry.name, topEntry.order)
        self:SafeSendChat(infoMsg, "RAID")
    end

    self:AnnounceSoftReserves(itemId)

    -- Send addon message so GuildOS users get the roll popup: the rule's buttons first (issue #334),
    -- which a client from before ignores, then the announce every client reads.
    self:SendAsk(duration)
    local payload = format("ANNOUNCE|%s|%d|%d|0", itemLink, duration, itemId or 0)
    self:SafeSendAddon(LootMaster.PREFIX, payload, "RAID")

    -- Start capturing /roll results from CHAT_MSG_SYSTEM
    self:StartListeningForRolls()

    -- Start countdown timer
    self:StartRollTimer(duration)
    self:ScheduleCountdownWarnings()

    -- Update UI — always open/refresh the ML roll frame
    self:ShowRollFrame()

    GuildOS:Print(L["Loot announced: "] .. itemLink .. " (" .. duration .. "s)")
end

----------------------------------------------------------------------
-- The raid warning that opens a roll. With the answers every guild had (MS and OS by a roll) it is the
-- line of before, by loot system. With answers of the guild's own (issue #334) it names the /roll of
-- the first two when they ask for one, and says that the rest, and any bid, go by the GuildOS window.
----------------------------------------------------------------------
function LootMaster:AnnounceLine(itemLink, duration)
    local LR = GuildOS.LootRule
    local rule = self:Rule()
    local list = LR:Responses(rule)
    local first, second = list[1], list[2]
    local function rolls(r) return r and (r.ask or "roll") == "roll" end
    if #list == 2 and first and second and first.key == "MS" and second.key == "OS" and rolls(first) and rolls(second) then
        local lootSystem = self:System()
        if lootSystem == "epgp" then
            return format(L["[EPGP] %s  -  /roll to ask, highest priority wins  -  %ds"], itemLink, duration)
        elseif lootSystem == "dkp" then
            return format(L["[DKP] %s  -  /roll to bid, highest DKP wins  -  %ds"], itemLink, duration)
        end
        return format(L["[ROLL] %s  -  /roll 1-100 = MS  -  /roll 1-99 = OS  -  %ds"], itemLink, duration)
    end
    local parts = {}
    if rolls(first) then parts[#parts + 1] = "/roll 1-100 = " .. LR:ResponseLabel(first) end
    if rolls(second) then parts[#parts + 1] = "/roll 1-99 = " .. LR:ResponseLabel(second) end
    if LR:HasBids(rule) then
        local _, min = LR:BidRules(rule)
        parts[#parts + 1] = format(L["bids from %d in the GuildOS window, or tell the loot master"], min)
    elseif #parts < #list then
        parts[#parts + 1] = L["other answers in the GuildOS window, or tell the loot master"]
    end
    return format(L["[ROLL] %s  -  %s  -  %ds"], itemLink, table.concat(parts, "  -  "), duration)
end

-- Whoever of the raid a queue of `rule` does not hold joins it, where the account says newcomers go.
function LootMaster:JoinQueues(rule)
    local P = GuildOS.Points
    if not (P and P.GetDB and P:GetDB()) then return end
    local queues = GuildOS.LootRule:Queues(rule)
    if #queues == 0 then return end
    local keys = P:RaidKeys()
    for _, q in ipairs(queues) do P:QueueJoin(q.key, keys, q.newcomer) end
end

-- A short name for the roll being opened: an answer names it, so one that comes late for the item
-- before is not read as one for this.
function LootMaster:NewSessionId()
    self.sessionSeq = ((self.sessionSeq or 0) + 1) % 16
    return string.format("%X", (GetServerTime() % 0x10000) * 16 + self.sessionSeq)
end

-- The rule's buttons, to the raiders' popups (issue #334).
function LootMaster:SendAsk(duration)
    local loot = self.activeLoot
    if not loot then return end
    loot.sid = loot.sid or self:NewSessionId()
    self:SafeSendAddon(LootMaster.PREFIX, "ASK|" .. loot.sid .. "|" .. GuildOS.LootRule:Encode(self:Rule(), duration), "RAID")
end

----------------------------------------------------------------------
-- Auto-Council: single clear wishlist winner - award directly
----------------------------------------------------------------------
function LootMaster:AutoCouncilAward(winner, itemLink, lootSlot, allCandidates)
    local orderStr
    if winner.isPrio then
        orderStr = L["Official Prio #1"]
    else
        orderStr = string.format(L["wishlist #%d"], winner.order)
    end

    -- Announce in raid
    self:SafeSendChat(
        string.format(L["[Wishlist] %s goes to %s (%s) - awaiting ML confirmation"], itemLink, winner.name, orderStr),
        "RAID_WARNING"
    )

    -- Show council result popup for ML to confirm
    self:ShowCouncilResultFrame(winner, itemLink, lootSlot, allCandidates)
end

----------------------------------------------------------------------
-- Restricted roll: only the tied top-priority players may roll.
-- Rolls from anyone else are silently ignored by ProcessSystemRoll.
----------------------------------------------------------------------
----------------------------------------------------------------------
-- Post a "[SR] Soft reserved by: ..." line to raid if any in-raid
-- players have this item on their soft reserve list.
-- Safe to call even when SoftRes is nil or has no imported data.
----------------------------------------------------------------------
function LootMaster:AnnounceSoftReserves(itemId)
    if not GuildOS.SoftRes or not itemId or itemId == 0 then return end
    local srList = GuildOS.SoftRes:GetInRaidReserves(itemId)
    if #srList == 0 then return end
    local names = {}
    for _, e in ipairs(srList) do names[#names+1] = e.name end
    self:SafeSendChat(format(L["[SR] Soft reserved by: %s"], table.concat(names, ", ")), "RAID")
end

function LootMaster:StartRestrictedRoll(tied, _allCandidates, itemLink, _lootSlot, itemId)
    -- Build restricted set (lowercase names for fast lookup)
    self.restrictedRollers = {}
    local names = {}
    for _, c in ipairs(tied) do
        self.restrictedRollers[strlower(c.name)] = true
        table.insert(names, c.name)
    end
    local orderStr = string.format(L["wishlist #%d"], tied[1].order)
    local nameStr = table.concat(names, ", ")

    -- Announce in RAID_WARNING — only listed players should roll
    local duration = self:RollTime()
    self:SafeSendChat(
        string.format(L["[ROLL] %s  -  Tie [%s]: %s  -  /roll 1-100 MS  -  /roll 1-99 OS  -  %ds"],
            itemLink, orderStr, nameStr, duration),
        "RAID_WARNING"
    )
    self:AnnounceSoftReserves(itemId or (self.activeLoot and self.activeLoot.itemId))

    -- Addon comm: show popup to GuildOS users who have the item on their wishlist
    itemId = itemId or (self.activeLoot and self.activeLoot.itemId) or 0
    self:SendAsk(duration)
    local payload = string.format("ANNOUNCE|%s|%d|%d|1", itemLink, duration, itemId)
    self:SafeSendAddon(LootMaster.PREFIX, payload, "RAID")

    -- Start capturing /roll (restricted list enforced in ProcessSystemRoll)
    self:StartListeningForRolls()

    -- Timer
    self:StartRollTimer(duration)
    self:ScheduleCountdownWarnings()

    -- Show roll tracker for ML
    self:ShowRollFrame()

    GuildOS:Print(string.format(L["|cffFFD700Wishlist tie|r [wishlist #%d]: %s - only they may roll (%ds)"],
        tied[1].order, nameStr, duration))
end

----------------------------------------------------------------------
-- Kept for compatibility: delegates to StartRestrictedRoll
----------------------------------------------------------------------
function LootMaster:AutoCouncilRoll(tied, itemLink, lootSlot, allCandidates)
    local itemId = self.activeLoot and self.activeLoot.itemId or 0
    self:StartRestrictedRoll(tied, allCandidates, itemLink, lootSlot, itemId)
end

----------------------------------------------------------------------
-- Council result frame: ML confirms or overrides auto-award
----------------------------------------------------------------------
function LootMaster:ShowCouncilResultFrame(winner, itemLink, lootSlot, allCandidates)
    local C = GuildOS.Colors
    local UI = GuildOS.UI

    if self.councilFrame then self.councilFrame:Hide() end

    local numRows = allCandidates and #allCandidates or 0
    local f = CreateFrame("Frame", "GuildOSCouncilFrame", UIParent, "BackdropTemplate")
    f:SetSize(460, 110 + numRows * 22)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.98)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(title, 13)
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText(L["Wishlist Council"])

    -- Item
    local itemText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(itemText, 12)
    itemText:SetPoint("TOP", 0, -26)
    itemText:SetText(itemLink or L["Unknown Item"])

    -- Winner line
    local CLASS_COLORS = RAID_CLASS_COLORS
    local cc = CLASS_COLORS[winner.class] or { r = 0.8, g = 0.8, b = 0.8 }
    local winText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(winText, 11)
    winText:SetPoint("TOP", 0, -44)
    local winLabel = winner.isPrio
        and L["|cffFFD700Official Prio #1|r"]
        or  string.format(L["|cff4CB8FFwishlist #%d|r"], winner.order)
    winText:SetText(string.format(">> |cff%02x%02x%02x%s|r - %s",
        cc.r * 255, cc.g * 255, cc.b * 255,
        winner.name, winLabel))

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\Buttons\\WHITE8x8")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 10, -60)
    sep:SetPoint("TOPRIGHT", -10, -60)
    sep:SetVertexColor(C.border.r, C.border.g, C.border.b, 0.4)

    -- Full priority list
    local yOff = -66
    if allCandidates then
        for i, c in ipairs(allCandidates) do
            local ccc = CLASS_COLORS[c.class] or { r = 0.8, g = 0.8, b = 0.8 }
            local ctx = LootMaster:GetPlayerContext(c.name)
            local attColor = ctx.att25 >= 60 and "00FF00" or ctx.att25 >= 40 and "FFFF00" or "FF4444"
            local row = f:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(row, 10)
            row:SetPoint("TOPLEFT", 14, yOff)
            local prefix = (i == 1) and "|cff00ff00>>|r " or "   "
            row:SetText(string.format(
                L["%s|cff%02x%02x%02x%s|r  |cff4CB8FFwishlist #%d|r  |cff%s%d%%|r"],
                prefix, ccc.r * 255, ccc.g * 255, ccc.b * 255,
                c.name, c.order,
                attColor, ctx.att25))
            yOff = yOff - 18
        end
    end

    -- Buttons
    local awardBtn = UI:CreateButton(f, L["Award to "] .. winner.name, 150, 26)
    awardBtn:SetPoint("BOTTOMLEFT", 10, 10)
    awardBtn:SetBackdropColor(0.0, 0.4, 0.0, 0.6)
    awardBtn:SetScript("OnClick", function()
        LootMaster:AwardLoot(winner.name)
        f:Hide()
    end)

    -- Send to disenchanter
    local deCouncilBtn = UI:CreateButton(f, L["Send to DE"], 110, 26)
    deCouncilBtn:SetPoint("LEFT", awardBtn, "RIGHT", 8, 0)
    deCouncilBtn:SetScript("OnClick", function()
        local loot = LootMaster.activeLoot
        if loot then
            LootMaster:SendToDisenchanter(loot.link, loot.slot, loot.itemId)
        else
            local iId = tonumber((itemLink or ""):match("item:(%d+)")) or 0
            LootMaster:SendToDisenchanter(itemLink, lootSlot, iId)
        end
        f:Hide()
    end)
    deCouncilBtn:SetScript("OnEnter", function(self)
        local deName = LootMaster:GetDisenchanter()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if deName and deName ~= "" then
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cff00ff00" .. deName .. "|r", 1, 1, 1)
        else
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cffFF4444" .. L["No disenchanter set"] .. "|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    deCouncilBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rollBtn = UI:CreateButton(f, L["Open Roll Instead"], 130, 26)
    rollBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    -- The three share the bottom edge; their labels (the winner's whole name among them)
    -- set how wide the popup has to be (issue #28).
    f:SetWidth(math.max(460, 10 + awardBtn:GetWidth() + 8 + deCouncilBtn:GetWidth() + 8
        + rollBtn:GetWidth() + 10))
    rollBtn:SetScript("OnClick", function()
        f:Hide()
        -- Fall back to normal announce
        LootMaster:DoNormalAnnounce(itemLink, lootSlot, LootMaster.activeLoot.itemId)
        LootMaster:ShowRollFrame()
    end)

    -- Close
    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnHide", function()
        LootMaster.testMode = false
    end)

    f:Show()
    self.councilFrame = f
end

----------------------------------------------------------------------
-- Handle incoming addon messages
----------------------------------------------------------------------
function LootMaster:OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= LootMaster.PREFIX then return end
    -- An addon message is somebody else's text: nothing of it is read before it is known to be text.
    if GuildOS.Compat.IsSecret(msg, channel, sender) or type(msg) ~= "string" then return end
    -- A sealed bid is whispered to the loot master (issue #334); nothing else comes by whisper.
    -- So is a vote of an anonymous council (issue #336).
    if channel == "WHISPER" then
        if msg:sub(1, 4) == "ANS|" then self:OnAnswerMessage(msg:sub(5), sender) end
        if msg:sub(1, 6) == "CVOTE|" and GuildOS.LootCouncil then GuildOS.LootCouncil:OnVoteMessage(msg:sub(7), sender) end
        return
    end
    if channel ~= "RAID" and channel ~= "RAID_LEADER" then return end

    local cmd, rest = msg:match("^(%w+)|(.+)$")
    if not cmd then return end

    if cmd == "ASK" then
        -- The buttons of the roll a loot master is about to announce (issue #334). Kept only until
        -- the ANNOUNCE that follows it, and only when every part of it is read.
        -- Read from the raid's master looter alone: anybody else's would send this client's answers,
        -- a sealed bid among them, to whoever asked.
        if not self:IsMasterLooter() and self:IsFromMasterLooter(sender) then
            local sid, encoded = rest:match("^(%x+)|(.+)$")
            local spec = sid and #sid <= 8 and GuildOS.LootRule:Decode(encoded)
            self.pendingAsk = spec and { sender = sender, sid = sid, spec = spec, at = GetTime() } or nil
        end

    elseif cmd == "ANS" then
        self:OnAnswerMessage(rest, sender)

    elseif cmd == "ROLL" or cmd == "BID" or cmd == "ACK" or cmd == "NO" then
        self:OnAnswerEcho(cmd, rest, sender)

    elseif cmd == "CVOTE" then
        -- A council member's vote (issue #336), to the master looter.
        if GuildOS.LootCouncil then GuildOS.LootCouncil:OnVoteMessage(rest, sender) end

    elseif cmd == "COPEN" or cmd == "CMEM" or cmd == "CCAND" or cmd == "CTALLY" or cmd == "CWHO" or cmd == "CNO"
        or cmd == "CCLOSE" then
        -- A council's vote as the master looter's client tells it (issue #336).
        if GuildOS.LootCouncil then GuildOS.LootCouncil:OnMessage(cmd, rest, sender) end

    elseif cmd == "ANNOUNCE" then
        -- The master looter announced an item - show roll popup if we're not ML. From anybody else it
        -- is not an announce: no popup, and the roll being answered stays the master looter's.
        if not self:IsMasterLooter() and self:IsFromMasterLooter(sender) then
            -- The buttons that came with it, from the same loot master a moment ago. With none (a
            -- loot master on a version from before) the popup is the MS / OS one, by /roll.
            local ask = self.pendingAsk
            self.pendingAsk = nil
            if ask and (ask.sender ~= sender or GetTime() - ask.at > ASK_WINDOW) then ask = nil end
            self.heard = nil

            local link, duration, itemId, wishlistOnly = rest:match("^(.+)|(%d+)|(%d+)|([01])$")
            if not link then
                -- Backwards compat: old format without wishlistOnly flag
                link, duration, itemId = rest:match("^(.+)|(%d+)|(%d+)$")
                wishlistOnly = "0"
            end
            duration = tonumber(duration) or 30
            itemId = tonumber(itemId) or 0

            -- Wishlist-only filter: only show popup if player has item on their wishlist
            if wishlistOnly == "1" and itemId > 0 then
                if not self:PlayerHasItemOnWishlist(itemId) then
                    return
                end
            end

            if ask then self.heard = { sender = sender, sid = ask.sid, spec = ask.spec, link = link } end
            self:ShowRollPopup(link, duration, itemId, ask and ask.spec)
        end

    elseif cmd == "WON" then
        self:OnWonMessage(rest, sender)

    elseif cmd == "UNDO" then
        -- An officer took an award back (issue #294): forget it here too.
        local who, id, at = rest:match("^([^|]+)|(%d+)|(%d+)$")
        local senderName = sender and sender:match("^([^-]+)") or ""
        if who and senderName ~= GuildOS.Compat.PlayerName() and GuildOS:IsOfficerByName(senderName) then
            LootMaster.ForgetAward(who, tonumber(id), tonumber(at))
        end

    elseif cmd == "AWARD" then
        -- ML awarded item.
        -- Extended format: playerName|itemId|quality|raidName|itemLink
        -- (raidName has no pipes; itemLink is the remainder so it can contain pipes)
        local awardedTo, awardQuality, awardRaid, link =
            rest:match("^([^|]+)|%d+|(%d+)|([^|]*)|(.+)$")
        if not awardedTo then
            -- Backward compat: old format playerName|itemLink
            awardedTo, link = rest:match("^([^|]+)|(.+)$")
        end
        if awardedTo and link then
            GuildOS:Print(string.format(L["|cffFFD700Loot:|r %s awarded to |cff00ff00%s|r"], link, awardedTo))

            -- Record to loot history only if the sender is an officer and not ourselves
            -- (the awarder already recorded locally in AwardLoot).
            local senderName = sender and sender:match("^([^-]+)") or ""
            if senderName ~= GuildOS.Compat.PlayerName()
                and GuildOS:IsOfficerByName(senderName)
                and GuildOS.LootTracker
            then
                local itemName = GuildOS.Compat.GetItemInfo(link)
                local quality  = tonumber(awardQuality) or 4
                GuildOS.LootTracker:RecordMLAward({
                    itemLink   = link,
                    itemName   = itemName or "",
                    quality    = quality,
                    player     = awardedTo,
                    playerKey  = GuildOS:GetPlayerKey(awardedTo),
                    count      = 1,
                    timestamp  = GetServerTime(),
                    raid       = awardRaid or "",
                    instanceID = 0,
                    fromML     = true,
                })
            end
        end
    end
end

----------------------------------------------------------------------
-- Register a player's /roll result (called from ProcessSystemRoll) or
-- an answer by the addon (TakeAnswer, issue #334).
-- name: bare player name (no realm);  rollType: the key of one of the
-- rule's answers ("MS" or "OS" unless the guild named others) or "PASS";
-- roll: the actual number the player rolled, nil for an answer that asks
-- for none;  extra: { bid, note, drawn (this client drew the roll),
-- quiet (no line to the raid) }.
-- Returns the row kept, or nil when a filter keeps the player out.
----------------------------------------------------------------------
function LootMaster:RegisterRoll(name, rollType, roll, extra)
    if not self.activeLoot then return end
    return self:InLootCore(self.RegisterRollNow, self, name, rollType, roll, extra)
end

function LootMaster:RegisterRollNow(name, rollType, roll, extra)
    extra = extra or {}

    local key = GuildOS:GetPlayerKey(name)
    local rule = self:Rule()
    local ctx = self:GetPlayerContext(name)

    -- Wishlist lookup
    local wishInfo = nil
    if GuildOS.Wishlist and self.activeLoot.itemId then
        local interest = GuildOS.Wishlist:GetItemInterest(self.activeLoot.itemId)
        if interest then
            for _, entry in ipairs(interest) do
                if strlower(entry.name) == strlower(name) then
                    wishInfo = { order = entry.order }
                    break
                end
            end
        end
    end

    -- Officer prio lookup
    local prioOrder = nil
    if GuildOS.db and GuildOS.db.lootPrios and self.activeLoot.itemId then
        local prioList = GuildOS.db.lootPrios[self.activeLoot.itemId]
        if prioList then
            for idx, entry in ipairs(prioList) do
                if strlower(entry.name or "") == strlower(name) then
                    prioOrder = idx
                    break
                end
            end
        end
    end

    -- Soft reserve lookup
    local srInfo = nil
    if GuildOS.SoftRes and self.activeLoot.itemId then
        for _, entry in ipairs(GuildOS.SoftRes:GetReserves(self.activeLoot.itemId)) do
            if strlower(entry.name or "") == strlower(name) then
                srInfo = { hard = entry.hard or false }
                break
            end
        end
    end

    -- The points as they stand now: the balance, and the two sides of EPGP with the pool's base GP,
    -- which a rule orders and filters by under the accounts "dkp", "ep" and "gp".
    local P = GuildOS.Points
    local pointsReady = P and P.GetDB and P:GetDB()
    local pKey = GuildOS:GetPlayerKey(name, GetRealmName())
    local ep, gp, gpBase, pr = 0, 0, 0, 0
    ctx.dkp = pointsReady and P:Get(pKey) or 0
    if pointsReady then
        gpBase = tonumber(pointsReady.config and pointsReady.config.baseGP) or 0
        ep, gp, pr = P:EP(pKey), P:GP(pKey) - gpBase, P:PR(pKey)
    end

    -- The counters the rule compares by (the +1, issue #334), as they stand now, a bonus account among
    -- them; and the place in each queue it keeps (issue #337), which whoever it never saw joins first.
    local accts
    if pointsReady then
        for _, a in ipairs(GuildOS.LootRule:Counters(rule)) do
            accts = accts or {}
            accts[a.key] = P:Counter(a.key, key)
        end
        for _, q in ipairs(GuildOS.LootRule:Queues(rule)) do
            accts = accts or {}
            if rollType ~= "PASS" and not P:QueuePos(q.key, key) then P:QueueJoin(q.key, { key }, q.newcomer) end
            accts[q.key] = P:QueuePos(q.key, key)
        end
    end

    -- Who may ask (the loot rule's filters, issue #333): below the attendance the guild asks for, a
    -- main spec answer is read as off spec; without the points to enter, a reserve on the item or room
    -- under the night's limit, no roll at all.
    local cand = {
        att25 = ctx.att25, recvCount = ctx.recvThisLockout, dkp = ctx.dkp, ep = ep, gp = gp, gpBase = gpBase,
        softRes = srInfo, accts = accts,
    }
    -- The raid's chat hears each thing about a player and an item once: an answer repeated, by a
    -- click or by a client sending it three hundred times, says nothing new, and a master looter's
    -- client that answered every one in chat could be disconnected for flooding in the middle of the loot.
    local told = self.activeLoot.told or {}
    self.activeLoot.told = told
    local function sayOnce(what, line)
        local id = key .. "|" .. what
        if told[id] then return end
        told[id] = true
        self:SafeSendChatAuto(line, "RAID")
    end

    local asked = rollType   -- what was clicked, before a filter reads it as another answer
    local answer, filter = GuildOS.LootRule:AnswerFor(cand, rollType, rule)
    if filter and not answer then
        sayOnce("out|" .. filter.k .. "|" .. tostring(filter.acct or ""), self:BlockedLine(name, filter, cand, rule))
        return
    end
    if filter then
        local what = "read|" .. filter.k .. "|" .. tostring(filter.from) .. "|" .. tostring(filter.to)
        if filter.k == "attendance" and filter.from == "MS" and filter.to == "OS" then
            sayOnce(what, string.format(
                L["[Loot] %s: MS converted to OS (attendance %d%% below minimum %d%%)"],
                name, ctx.att25, filter.min))
        else
            sayOnce(what, string.format(L["[Loot] %s: %s read as %s (%s)"], name,
                self:AnswerLabel(filter.from), self:AnswerLabel(filter.to), self:FilterReason(filter, cand, rule)))
        end
        rollType = answer
    end

    -- Class from raid unit or stored member data
    local class = "UNKNOWN"
    local numMembers = GetNumGroupMembers() or 0
    if numMembers > 0 then
        for i = 1, numMembers do
            local unit = "raid" .. i
            local uName, uSecond, classFile = GuildOS.Compat.UnitIdentity(unit)
            if uName and (uName == name
                or (GuildOS.Client.has.surnames and self:WholeRollerName(name, uName, uSecond))) then
                class = classFile or "UNKNOWN"
                break
            end
        end
    end
    if class == "UNKNOWN" then
        local memberData = GuildOS.db.members and GuildOS.db.members[pKey]
        if memberData and memberData.class then
            class = memberData.class
        elseif name == GuildOS.Compat.PlayerName() then
            class = select(2, UnitClass("player")) or "UNKNOWN"
        end
    end

    self.rolls[key] = {
        name       = name,
        class      = class,
        rollType   = rollType,
        live       = true,   -- read from the accounts here: read again when the roll ends (RereadAccounts)
        asked      = asked ~= rollType and asked or nil,   -- for the award's record (LootRule:Why)
        roll       = roll,
        rolled     = roll ~= nil and rollType ~= "PASS" or (extra.drawn and true) or nil,
        drawn      = extra.drawn or nil,
        bid        = extra.bid,
        note       = (extra.note and extra.note ~= "") and extra.note or nil,
        accts      = accts,
        wishlist   = wishInfo,
        prioOrder  = prioOrder,
        softRes    = srInfo,
        att25      = ctx.att25,
        recvCount  = ctx.recvThisLockout,
        dkp        = ctx.dkp,
        pr         = pr,
        ep         = ep,
        gp         = gp,
        gpBase     = gpBase,
    }

    -- Announce prio or wishlist position to raid
    if prioOrder and not extra.quiet then
        sayOnce("prio|" .. rollType, string.format(L["[Loot] %s: %s (Official Prio #%d)"],
            name, rollType, prioOrder))
    elseif wishInfo and not extra.quiet then
        sayOnce("wish|" .. rollType, string.format(L["[Loot] %s: %s (Wishlist #%d)"],
            name, rollType, wishInfo.order))
    end

    -- Refresh ML roll frame
    if self.rollFrame and self.rollFrame:IsShown() then
        self:RefreshRollFrame()
    end
    return self.rolls[key]
end

-- Why a filter of the rule failed a candidate, in words. Each one by its own literal key.
function LootMaster:FilterReason(f, c, rule)
    if f.k == "attendance" then
        return string.format(L["attendance %d%% below minimum %d%%"], c.att25 or 0, f.min)
    elseif f.k == "reserved" then
        return L["the item was not reserved"]
    elseif f.k == "received" then
        return string.format(L["%d items received tonight, the limit is %d"], c.recvCount or 0, f.max)
    end
    local acct = f.k == "points" and "dkp" or f.acct
    local has = GuildOS.LootRule:Held(c, acct, rule)
    if acct == "dkp" then return string.format(L["%d points, %d needed"], has, f.min) end
    local counter = GuildOS.LootRule:Counter(acct, rule)
    return string.format(L["%s: %d, %d needed"], (counter and counter.name) or acct:upper(), has, f.min)
end

-- The line the raid reads when a filter keeps somebody out of the roll. The points' own, a roll that
-- costs more to enter than the roller holds (issue #309), is the line of before.
function LootMaster:BlockedLine(name, f, c, rule)
    if f.k == "points" or (f.k == "account" and f.acct == "dkp") then
        return string.format(L["[Loot] %s: not in this roll (%d points, %d needed to enter)"], name, c.dkp or 0, f.min)
    end
    return string.format(L["[Loot] %s: not in this roll (%s)"], name, self:FilterReason(f, c, rule))
end

----------------------------------------------------------------------
-- Answers by the addon (issue #334)
----------------------------------------------------------------------
-- Why an answer was not taken, in words. `n` is the figure the reason carries, when it has one.
-- Each one by its own literal key, so every language file finds it.
function LootMaster:WhyNot(why, n)
    if why == "closed" then return L["No roll is open."] end
    if why == "unknown" then return L["That answer is not one of this roll's."] end
    if why == "note" then return L["That answer needs a note."] end
    if why == "bid" then return string.format(L["A bid must be a whole number of at least %d."], n or 0) end
    if why == "balance" then return L["That bid is more than the points you hold."] end
    if why == "low" then return string.format(L["That bid is too low: at least %d now."], n or 0) end
    if why == "held" then return L["Your bid stands: an open bid can be raised, never withdrawn or changed."] end
    if why == "raid" then return L["Only a raid member can answer."] end
    if why == "ml" then return L["You are not the Master Looter."] end
    return L["Not in this roll."]
end

-- A note as it is kept: no colour code, no control character, and short.
local function cleanNote(note)
    return (tostring(note or ""):gsub("[|%c]", ""):sub(1, NOTE_MAX))
end

-- The loot master's side: one answer of `name`, a raid member, to the open roll. `key` is one of the
-- rule's answers or "PASS". The roll an answer asks for is drawn here and nowhere else; a bid is held
-- to the rule (the least bid, the step over the best one when bids are open) and to the points the
-- bidder holds. Returns the row kept, or nil, why and the figure the reason carries.
function LootMaster:TakeAnswer(name, key, bid, note)
    local loot = self.activeLoot
    if not loot or loot.ended or loot.delivered then return nil, "closed" end
    return self:InLootCore(self.TakeAnswerNow, self, name, key, bid, note)
end

function LootMaster:TakeAnswerNow(name, key, bid, note)
    local LR = GuildOS.LootRule
    local rule = self:Rule()
    local rkey = GuildOS:GetPlayerKey(name)
    note = cleanNote(note)

    -- An open bid stands, as in any open auction: whoever holds one may raise it on the same answer,
    -- and nothing else. A bidder used to push the price up and then pass, leaving the next one to pay
    -- a price nobody was bidding against any more. Sealed bids, which nobody sees, change freely.
    local held = self.rolls[rkey]
    if held and held.bid and held.rollType ~= "PASS" and key ~= held.rollType
        and GuildOS.LootRule:HasBids(self:Rule()) and not GuildOS.LootRule:BidRules(self:Rule()) then
        return nil, "held"
    end

    if key == "PASS" then
        -- Out of the roll, bid and all; the roll already read or drawn stays the player's (KeepRoll)
        -- in case the answer changes again.
        local kept = self:KeepRoll(name)
        local passed = self:RegisterRoll(name, "PASS", kept and kept.roll or 0,
            { drawn = kept and kept.drawn or nil, quiet = true })
        if not passed then return nil, "out" end
        return passed
    end
    local response, place = LR:Response(key, rule)
    if not response then return nil, "unknown" end
    -- The answer's own flag, or the council's, which reads every note (issue #336).
    if LR:NeedsNote(response, rule) and note == "" then return nil, "note" end
    local ask = response.ask or "roll"
    local row

    if ask == "bid" then
        local sealed, min, step = LR:BidRules(rule)
        bid = tonumber(bid)
        if not bid or bid ~= math.floor(bid) or bid < min or bid > LR.MAX_BID then return nil, "bid", min end
        local P = GuildOS.Points
        local balance = (P and P.GetDB and P:GetDB() and P:Get(GuildOS:GetPlayerKey(name, GetRealmName()))) or 0
        if bid > balance then return nil, "balance" end
        if not sealed then
            -- Open: over the best bid of the same answer by a step, and never back down from one's own.
            local least = min
            for k, r in pairs(self.rolls) do
                if r.bid and r.rollType == key and r.rollType ~= "PASS" then
                    least = math.max(least, k == rkey and (r.bid + 1) or (r.bid + step))
                end
            end
            if bid < least then return nil, "low", least end
        end
        row = self:RegisterRoll(name, key, nil, { bid = bid, note = note })
    elseif ask == "roll" then
        -- One roll a player and an item: answering again keeps the number, whatever was answered
        -- in between and whoever entered it.
        local kept = self:KeepRoll(name)
            or self:KeepRoll(name, math.random(1, place == 2 and ROLL_TOP_SECOND or ROLL_TOP), true)
        row = self:RegisterRoll(name, key, kept.roll, { drawn = kept.drawn or nil, note = note })
    else
        row = self:RegisterRoll(name, key, nil, { note = note })
    end
    if not row then return nil, "out" end
    return row
end

-- The loot master's side: an ANS message. The answer is its sender's, who has to be in the raid (and,
-- in a roll for a tie, one of the tied); what the message says about anybody else is never read.
function LootMaster:OnAnswerMessage(rest, sender)
    local loot = self.activeLoot
    if not (loot and loot.sid and not loot.ended) then return end
    if not self:IsMasterLooter() then return end
    if #rest > 120 then return end
    local sid, key, bid, note = rest:match("^(%x+)|([A-Z0-9]+)|(%d+)|?(.*)$")
    if not sid or sid ~= loot.sid or #key > 8 or #bid > 7 then return end
    local name = self:RaidRollerName(sender)
    if not name then return end
    if self.restrictedRollers and not self.restrictedRollers[strlower(name)] then return end

    -- One raider's client cannot make this one talk without end. The answer it just sent, sent again
    -- within a few seconds, is dropped with no reply (the first one was answered; a raider who clicks
    -- again later, with more points by then, is read again); and past a budget no answer of that
    -- raider's for this item is read at all. Nothing is said either way: a reply is what a flood wants.
    loot.heardFrom = loot.heardFrom or {}
    local from = loot.heardFrom[name] or { n = 0 }
    loot.heardFrom[name] = from
    local said, now = key .. "|" .. bid .. "|" .. note, GetTime()
    if from.last == said and now - (from.at or 0) < ANSWER_REPEAT then return end
    from.n = from.n + 1
    if from.n > ANSWER_BUDGET then return end
    from.last, from.at = said, now

    local row, why, n = self:TakeAnswer(name, key, tonumber(bid), note)
    self:EchoAnswer(name, row, why, n)
end

-- What the loot master did with an answer, to the raid: the roll it drew, an open bid, or that the
-- answer is in. A sealed bid is only acknowledged. A refusal says why, without the bidder's figures.
-- `byClick`: the loot master typed the answer in, so the bid's line reaches the raid on WoW: Forever
-- too (issue #63). The echoes take the throttled queue: a whole raid answers within a few seconds.
function LootMaster:SendEcho(payload)
    if IsInRaid() and not self.testMode then
        GuildOS.Compat.SendAddonMessage(LootMaster.PREFIX, payload, "RAID", nil, "NORMAL")
    end
end

function LootMaster:EchoAnswer(name, row, why, n, byClick)
    local loot = self.activeLoot
    if not (loot and loot.sid) then return end
    local LR = GuildOS.LootRule
    local payload
    if not row then
        payload = string.format("NO|%s|%s|%s|%d", loot.sid, name, why or "out", n or 0)
    elseif row.rollType == "PASS" then
        payload = string.format("ACK|%s|%s|PASS", loot.sid, name)
    elseif row.bid then
        local sealed = LR:BidRules(self:Rule())
        if sealed then
            payload = string.format("ACK|%s|%s|%s", loot.sid, name, row.rollType)
        else
            payload = string.format("BID|%s|%s|%s|%d", loot.sid, name, row.rollType, row.bid)
            local say = byClick and self.SafeSendChat or self.SafeSendChatAuto
            say(self, string.format(L["[Loot] %s: %s, bid %d"], name,
                self:AnswerLabel(row.rollType), row.bid), "RAID")
        end
    elseif row.drawn then
        -- The raid's chat hears the rolls drawn here in one line, when the roll ends (EndRolling).
        payload = string.format("ROLL|%s|%s|%s|%d", loot.sid, name, row.rollType, row.roll)
    else
        payload = string.format("ACK|%s|%s|%s", loot.sid, name, row.rollType)
    end
    self:SendEcho(payload)
end

-- What the button of the answer `key` says, in the rule in force.
function LootMaster:AnswerLabel(key)
    local r = GuildOS.LootRule:Response(key, self:Rule())
    return r and GuildOS.LootRule:ResponseLabel(r) or key
end

-- The loot master's side: an answer typed in for a raider who has no GuildOS, or the loot master's
-- own. `typed` is the raider's name as typed, in any case. Returns the row, or nil, why and a figure.
function LootMaster:EnterAnswer(typed, key, bid, note)
    if not self:IsMasterLooter() then return nil, "ml" end
    typed = strtrim(tostring(typed or ""))
    local name
    if typed ~= "" and strlower(typed) == strlower(GuildOS.Compat.PlayerName() or "") then
        name = self:RaidRollerName(GuildOS.Compat.PlayerName())
    elseif typed ~= "" then
        local numMembers = GetNumGroupMembers() or 0
        for i = 1, numMembers do
            local uName = GuildOS.Compat.UnitIdentity("raid" .. i)
            if uName and strlower(uName) == strlower(typed) then
                name = self:RaidRollerName(uName)
                break
            end
        end
        if not name and self.testMode then name = typed end
    end
    if not name then return nil, "raid" end
    -- What the raider's own client sent last is no longer what stands: the same answer from it counts again.
    local heardFrom = self.activeLoot and self.activeLoot.heardFrom and self.activeLoot.heardFrom[name]
    if heardFrom then heardFrom.last = nil end
    local row, why, n = self:TakeAnswer(name, key, bid, note)
    self:EchoAnswer(name, row, why, n, true)
    if row and self.rollFrame and self.rollFrame:IsShown() then self:RefreshRollFrame() end
    return row, why, n
end

-- A raider's side: the button clicked in the roll popup. The answer goes to the loot master who
-- announced the item: over the raid, or by whisper when it is a sealed bid.
function LootMaster:SendAnswer(key, bid, note)
    local heard = self.heard
    if not heard then return false end
    bid = math.max(0, math.floor(tonumber(bid) or 0))
    local msg = string.format("ANS|%s|%s|%d", heard.sid, key, bid)
    note = cleanNote(note)
    if note ~= "" then msg = msg .. "|" .. note end
    if heard.spec.sealed and bid > 0 then
        if IsInRaid() and not self.testMode then
            GuildOS:NoteWhisper(heard.sender)
            GuildOS.Compat.SendAddonMessageNow(LootMaster.PREFIX, msg, "WHISPER", heard.sender)
        end
    else
        self:SafeSendAddon(LootMaster.PREFIX, msg, "RAID")
    end
    return true
end

-- Whether `name`, as a loot master's client wrote it, is this player. On a client with surnames the
-- loot master may hold the first name alone (issue #48): the first name then says so.
local function isSelf(name)
    local me = GuildOS.Compat.PlayerName() or ""
    if name == me then return true end
    return GuildOS.Client.has.surnames and name:match("^%S+") == me:match("^%S+") or false
end

-- A raider's side: what the loot master did with an answer. Read only from the loot master whose
-- roll this client is answering; it shows, and changes nothing a roll is decided by.
function LootMaster:OnAnswerEcho(cmd, rest, sender)
    local heard = self.heard
    if not heard or sender ~= heard.sender or not self:IsFromMasterLooter(sender) then return end
    local sid, name, key, number = rest:match("^(%x+)|([^|]+)|(%w+)|?(%d*)$")
    if sid ~= heard.sid or #name > 64 or #key > 8 or #number > 7 then return end
    number = tonumber(number) or 0
    local popup = self.rollPopup
    local function reply(text)
        if isSelf(name) then
            GuildOS:Print(text)
            if popup and popup.replyText then popup.replyText:SetText(text) end
        end
    end
    local label = key
    for _, r in ipairs(heard.spec.responses) do
        if r.key == key then label = r.label end
    end
    if cmd == "ROLL" then
        reply(string.format(L["You rolled |cff00ff00%d|r (%s) for %s"], number, label, heard.link or L["item"]))
    elseif cmd == "BID" then
        if not heard.high or number > heard.high then
            heard.high = number
            if popup and popup.highText then
                popup.highText:SetText(string.format(L["Highest bid: %d (%s)"], number, name))
            end
        end
        reply(string.format(L["Your bid of %d (%s) is in."], number, label))
    elseif cmd == "ACK" then
        reply(key == "PASS" and L["You passed."] or string.format(L["Your answer (%s) is in."], label))
    elseif cmd == "NO" then
        reply("|cffFF4444" .. self:WhyNot(key, number) .. "|r")
    end
end

----------------------------------------------------------------------
-- The counters and the places in a queue each row holds, read again as they stand now. A row keeps
-- what its player held when they answered; an award undone, or another officer's entry, in the
-- seconds the roll stays open moves a queue or a counter, and the roll ended by places nobody held any
-- more. Only rows this client read from the accounts (`live`).
----------------------------------------------------------------------
function LootMaster:RereadAccounts(rule)
    local P, LR = GuildOS.Points, GuildOS.LootRule
    if not (P and P.GetDB and P:GetDB()) then return end
    local counters, queues = LR:Counters(rule), LR:Queues(rule)
    if #counters == 0 and #queues == 0 then return end
    for key, r in pairs(self.rolls) do
        if r.live then
            r.accts = r.accts or {}
            for _, a in ipairs(counters) do r.accts[a.key] = P:Counter(a.key, key) end
            for _, q in ipairs(queues) do r.accts[q.key] = P:QueuePos(q.key, key) end
        end
    end
end

----------------------------------------------------------------------
-- End rolling and display results
----------------------------------------------------------------------
-- `byClick`: the End Rolling button. The roll timer ends it without one, and on WoW: Forever
-- its winner line then only reaches the loot master (issue #63); the Award click announces.
function LootMaster:EndRolling(byClick)
    if not self.activeLoot then return end
    local say = byClick and self.SafeSendChat or self.SafeSendChatAuto

    self:StopListeningForRolls()
    self.restrictedRollers = nil

    self:StopRollTimer()

    -- Sort rolls: MS first (by wishlist order then roll), then OS (by roll)
    local sorted = {}
    for _, r in pairs(self.rolls) do
        if r.rollType ~= "PASS" then
            table.insert(sorted, r)
        end
    end

    -- In DKP the winner is who the ML window puts on top: highest DKP among MS, then the roll
    -- (issue #294). The announcement used to ignore DKP and name somebody else.
    -- The loot rule's order (issue #333): the same one the Master Loot window shows.
    local rule = self:Rule()
    self:InLootCore(self.RereadAccounts, self, rule)
    GuildOS.LootRule:Sort(sorted, rule)

    self.activeLoot.sortedResults = sorted
    self.activeLoot.ended = true

    -- The rolls this client drew for the raiders' buttons (issue #334), in one line for the raid's
    -- chat: whoever has no GuildOS sees every number the winner was picked from, as with /roll.
    local drawn = {}
    for _, r in ipairs(sorted) do
        if r.drawn and r.roll then
            drawn[#drawn + 1] = string.format("%s %s %d", r.name, r.rollType, r.roll)
        end
    end
    if #drawn > 0 then
        local line = table.concat(drawn, ", ")
        if #line > ROLLS_LINE_MAX then line = line:sub(1, ROLLS_LINE_MAX):gsub(",[^,]*$", "") .. ", ..." end
        say(self, string.format(L["[Rolls] %s"], line), "RAID")
    end

    -- A rule whose items a council decides (issue #336): with more than one candidate the council
    -- votes, and the raid is told so in place of a winner. One candidate needs no vote.
    local Council = GuildOS.LootCouncil
    local council = Council and GuildOS.LootRule:Council(rule) and #sorted > 1 and self:IsMasterLooter()
    if council then
        if not self.activeLoot.council then
            local session = Council:Open(self.activeLoot, sorted, rule)
            say(self, string.format(L["[Council] %s: %d candidates, the council votes (%ds)"], self.activeLoot.link,
                #session.candidates, session.seconds), "RAID_WARNING")
        end
    elseif #sorted > 0 then
        local winner = sorted[1]
        local wishStr = ""
        if winner.prioOrder then
            wishStr = string.format(L[" [Official Prio #%d]"], winner.prioOrder)
        elseif winner.softRes then
            wishStr = winner.softRes.hard and L[" [Hard Reserve]"] or L[" [Soft Reserve]"]
        elseif winner.wishlist then
            wishStr = string.format(L[" [Wishlist #%d]"], winner.wishlist.order)
        end
        -- What put the winner ahead of the next candidate, when it was not the roll itself.
        local decided = GuildOS.LootRule:DecidedBy(winner, sorted[2], rule)
        self.activeLoot.decidedBy = decided
        if decided and decided ~= "roll" and wishStr == "" then
            wishStr = string.format(L[" [by %s]"], GuildOS.LootRule:Label(decided))
        end
        -- The answer by its button's name, and what it asked for: the roll, the bid, or neither (#334).
        local label = self:AnswerLabel(winner.rollType)
        if winner.bid then
            say(self, string.format(L["[WINNER] %s - %s (bid %d)%s - %s"],
                winner.name, label, winner.bid, wishStr, self.activeLoot.link), "RAID_WARNING")
        elseif winner.roll and GuildOS.LootRule:BonusOf(winner, rule) > 0 then
            -- The roll and what the bonus account added to it, each by itself (issue #337).
            say(self, string.format(L["[WINNER] %s - %s (%d + %d)%s - %s"], winner.name, label, winner.roll,
                GuildOS.LootRule:BonusOf(winner, rule), wishStr, self.activeLoot.link), "RAID_WARNING")
        elseif winner.roll then
            say(self, string.format(L["[WINNER] %s - %s (%d)%s - %s"],
                winner.name, label, winner.roll, wishStr, self.activeLoot.link), "RAID_WARNING")
        else
            say(self, string.format(L["[WINNER] %s - %s%s - %s"],
                winner.name, label, wishStr, self.activeLoot.link), "RAID_WARNING")
        end
    else
        say(self, L["[Roll] No roll received for "] .. self.activeLoot.link, "RAID_WARNING")
        -- Nobody asked (issue #335): a rule with an exception for that sends the item where it says.
        -- With none, the loot master's Send to Disenchant button, as always.
        local loot = self.activeLoot
        local unclaimed = loot.item and GuildOS.LootRule:ExceptionFor(loot.baseRule or rule, loot.item, true)
        if unclaimed and unclaimed.to and self:IsMasterLooter() then
            self:SendToDestination(unclaimed, loot.link, loot.slot, loot.itemId, "norolls")
        end
    end

    -- Refresh UI
    if self.rollFrame and self.rollFrame:IsShown() then
        self:RefreshRollFrame()
    end
end

----------------------------------------------------------------------
-- Award loot to a player (Gargul-style two-path distribution)
----------------------------------------------------------------------
-- `free`: the item goes to a fixed destination (the bank, the disenchanter of an exception, issue
-- #335) and costs nobody anything.
function LootMaster:AwardLoot(playerName, silent, free)
    if not self.activeLoot then return end
    if not self:IsMasterLooter() then
        GuildOS:Print(L["You are not the Master Looter."])
        return
    end
    -- Everything the award reads and writes is the core's the item was announced under.
    return self:InLootCore(self.AwardLootNow, self, playerName, silent, free)
end

function LootMaster:AwardLootNow(playerName, silent, free)

    local itemLink = self.activeLoot.link
    -- The winner's answer, when the item was rolled for: what it costs and whether it counts for the
    -- +1 come from it (issue #334). An item given straight from the loot window has none.
    local LR = GuildOS.LootRule
    local rule = self:Rule()
    local row = self.rolls[GuildOS:GetPlayerKey(playerName)]
    local response = row and LR:Response(row.rollType, rule)
    -- Default to 0 so the "%d" in the AWARD payload (and history record) never sees nil
    -- for malformed/non-item links. The receiver skips this field with "%d+", so 0 is safe.
    local itemId = self.activeLoot.itemId or 0
    local slot = self.activeLoot.slot
    local awarded = false

    -- Path 1: ML loot window open + ML API available -> GiveMasterLoot
    if self.lootWindowOpen and slot and GiveMasterLoot and GetMasterLootCandidate then
        local numCandidates = 40
        local found, matches = nil, 0
        for i = 1, numCandidates do
            local candidateName = GetMasterLootCandidate(slot, i)
            if candidateName then
                local cName = candidateName:match("^([^-]+)")
                if cName == playerName then
                    found, matches = i, 1
                    break
                elseif GuildOS.Client.has.surnames and self:WholeRollerName(cName, playerName) then
                    found, matches = i, matches + 1
                end
            end
        end
        -- An item handed out does not come back: a first name alone gives it only when it can be nobody
        -- else's. Two who share one go to the trade below (issue #48).
        if matches == 1 then
            GiveMasterLoot(slot, found)
            awarded = true
        end
    end

    -- Path 2: No ML API or loot window closed -> queue for trade
    if not awarded then
        local isMe = (playerName == GuildOS.Compat.PlayerName())
        if not isMe then
            self:QueueForTrade(playerName, itemLink, itemId)
        end
    end

    -- Gather extra context for history and broadcast
    local _, _, itemQuality = GuildOS.Compat.GetItemInfo(itemLink)
    itemQuality = itemQuality or 4
    local zoneName, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    local raidName = ""
    local RT = GuildOS.RaidTracker
    if RT and RT.RAID_INSTANCES then
        -- A raid no list knows (every one on WoW: Forever) by the name the game gives (#90).
        raidName = RT.RAID_INSTANCES[instanceID]
            or (instanceType == "raid" and RT:IsTracked(instanceID) and zoneName) or ""
    end
    -- Broadcast award (extended format: playerName|itemId|quality|raidName|itemLink)
    -- Peers with GuildOS will record this to their loot history after verifying
    -- the sender is an officer.
    local payload = string.format("AWARD|%s|%d|%d|%s|%s", playerName, itemId, itemQuality, raidName, itemLink)
    self:SafeSendAddon(LootMaster.PREFIX, payload, "RAID")

    -- Announce (skipped when silent=true, e.g. SendToDisenchanter already announced)
    if not silent then
        self:SafeSendChat(string.format(L["[Loot] %s delivered to %s"], itemLink, playerName), "RAID")
    end

    -- Save to LootMaster's own award log (for undo / ML reference)
    local awardedAt = GetServerTime()
    local lootCore = self.activeLoot.core
    local awardHistory = GuildOS.CoreManager and GuildOS.CoreManager:GetAwardHistory(lootCore)
                         or (GuildOS.db.lootMaster and GuildOS.db.lootMaster.awardHistory) or {}
    local award = {
        core = lootCore,   -- an undo gives back into the accounts the award took from
        link = itemLink,
        itemId = itemId,
        player = playerName,
        timestamp = awardedAt,
        received = awarded,
    }
    table.insert(awardHistory, 1, award)
    self.lastAwardCore = lootCore
    while #awardHistory > 200 do
        table.remove(awardHistory)
    end

    -- Record to the central loot history (ML-awarded items only, officer action), with why the winner
    -- got it (issue #336).
    if GuildOS.LootTracker then
        local itemName = GuildOS.Compat.GetItemInfo(itemLink)
        GuildOS.LootTracker:RecordMLAward({
            why        = self:AwardWhy(playerName, rule, free),
            itemLink   = itemLink,
            itemName   = itemName or "",
            quality    = itemQuality,
            player     = playerName,
            playerKey  = GuildOS:GetPlayerKey(playerName),
            count      = 1,
            timestamp  = awardedAt,
            raid       = raidName,
            instanceID = instanceID,
            fromML     = true,
        })
    end

    -- DKP: charge the winner when the guild runs the points system and a
    -- per-item cost is configured (cost 0 = informational standings only).
    -- A rule that names what the winner pays (their bid, issue #334) charges whatever the loot system.
    local pointsReady = GuildOS.Points and GuildOS.Points.GetDB and GuildOS.Points:GetDB()
    local entryEffect = LR:EntryEffect(rule)
    if pointsReady and not free and (GuildOS:LootSystemUsesPoints(self:System()) or LR:ChargeEffect(rule) or entryEffect)
        and GuildOS:IsOfficer() then
        local pKey = GuildOS:GetPlayerKey(playerName)
        -- The price to enter the roll (issue #309): everyone who asked pays it, and whoever lost gets
        -- part of it back. Only for the item that was rolled, and what each paid is kept for an undo.
        local rolled = self.activeLoot and self.activeLoot.link == itemLink and self.activeLoot.sortedResults
        if rolled then
            local asked = {}
            for _, r in ipairs(rolled) do asked[#asked + 1] = GuildOS:GetPlayerKey(r.name) end
            -- The rule's own price and refund when it names them ("entry"), else the points' settings.
            local paid = GuildOS.Points:ChargeEntry(asked, pKey, GuildOS.Compat.GetItemInfo(itemLink) or itemLink,
                entryEffect and entryEffect.value, entryEffect and (entryEffect.refund or 0) * 100)
            if #paid > 0 then award.paid = paid end
        end
        -- The item's price: the guild's own for it, its GP in EPGP, else the one cost per item (#319).
        -- Then what the rule says of it (issue #334): the winner's bid, or one step over the bid they
        -- beat, and the share of it their answer pays (off spec for half, a free answer for nothing).
        -- The points history keeps both the bid and what was charged.
        local others = {}
        for _, r in pairs(self.rolls) do others[#others + 1] = r end
        -- A price that is a share of what the winner holds ("fraction", "all") reads the balance now.
        local cost = LR:PriceFor(row, others, GuildOS.Points:PriceOf(itemLink, self:System()), rule, GuildOS.Points:Get(pKey))
        if cost > 0 then
            local reason = GuildOS.Compat.GetItemInfo(itemLink) or itemLink
            if row and row.bid then
                reason = string.format(L["%s (bid %d, paid %d)"], reason, row.bid, cost)
            end
            GuildOS.Points:Charge(pKey, cost, reason)
            -- What an undo gives back (issue #294).
            award.charged, award.chargedKey = cost, pKey
            self:SafeSendChat(string.format(L["[DKP] %s charged %d points for %s"],
                playerName, cost, itemLink), "RAID")
            -- Zero-sum (issue #337): what was charged goes back to whoever is in the raid, in equal
            -- shares, the winner's own among them. What each got is kept for an undo.
            if LR:Splits(rule) then
                local shares = GuildOS.Points:Split(GuildOS.Points:RaidKeys(), cost,
                    string.format(L["Share of %s"], GuildOS.Compat.GetItemInfo(itemLink) or itemLink))
                if #shares > 0 then
                    award.split = shares
                    self:SafeSendChat(string.format(L["[DKP] %d points each to %d raiders for %s"],
                        shares[1].amount, #shares, itemLink), "RAID")
                end
            end
        end
    end

    -- What the award changes on the rule's counters and queues (CounterEffects). Whoever the loot master
    -- is. An item given with no answer (straight from the loot window) moves none.
    if pointsReady and response then
        local pKey = GuildOS:GetPlayerKey(playerName)
        local opBase = self:AwardOp(self.activeLoot.sid, itemId, pKey)
        self:CounterEffects(rule, response, pKey, opBase, award)
        -- A master looter who is no officer cannot tell the guild's accounts anything: the entries above
        -- stay on this client. The raid's officers hear who won with which answer and make the same
        -- entries themselves, under the same names, once (OnWonMessage).
        if award.plus and opBase and not GuildOS:IsOfficer() then
            self:SafeSendAddon(LootMaster.PREFIX, string.format("WON|%s|%d|%s|%s", self.activeLoot.sid, itemId,
                row.rollType, playerName), "RAID")
        end
    end

    if awarded then
        GuildOS:Print(itemLink .. L[" given to |cff00ff00"] .. playerName .. "|r")
    else
        GuildOS:Print(itemLink .. L[" awarded to |cff00ff00"] .. playerName .. L["|r - trade to deliver."])
    end

    if self.activeLoot then self.activeLoot.delivered = true end
    self.activeLoot = nil
    self.rolls = {}
    -- Given before its time ran out: its timer and its /roll lines are over with it.
    self:StopListeningForRolls()
    self:StopRollTimer()
end

----------------------------------------------------------------------
-- What an award changes on the rule's counters, in the rule's order:
--   * "add" (the +1, issue #334): an answer that counts adds to the winner's counter;
--   * "reset": the winner's counter goes back to nothing (a wait that ends with the item);
--   * "charge" on a counter: a fixed figure or a share of it comes off, by the answer's cost;
--   * "bottom": the winner drops to the end of a queue (Suicide Kings, issue #337).
-- `opBase` names each entry after the award (AwardOp), so the master looter's client and every officer
-- who hears of the award make it once between them. `award` is the master looter's record of the award:
-- each move is kept on it for an undo, and only with it does a queue move, since a queue's order is the
-- master looter's client's to say.
----------------------------------------------------------------------
function LootMaster:AwardOp(sid, itemId, pKey)
    if not sid then return nil end
    return string.format("W%s-%d-%s", sid, itemId or 0, pKey)
end

function LootMaster:CounterEffects(rule, response, pKey, opBase, award)
    local LR, P = GuildOS.LootRule, GuildOS.Points
    local made, moves = 0, 0
    -- One entry moves a counter by a hundred at most (Points): a larger move takes several.
    local function move(acct, delta)
        local counter = LR:Counter(acct, rule)
        local reset = counter and counter.reset or "never"
        while delta ~= 0 do
            local step = math.max(-100, math.min(100, delta))
            moves = moves + 1
            local e = P:AddCounter(acct, pKey, step, reset, nil, opBase and (opBase .. "." .. moves) or nil)
            if not e then return end
            made = made + 1
            if award then
                award.plus = award.plus or {}
                award.plus[#award.plus + 1] = { acct = e.acct, key = pKey, value = step, reset = e.rs, per = e.per }
            end
            delta = delta - step
        end
    end
    for _, effect in ipairs(rule.effects or {}) do
        local counter = LR:Counter(effect.acct, rule)
        local bonus = counter and counter.type == "bonus"
        if effect.k == "add" and response.plus then
            -- An account with a cap (a bonus, issue #337) never grows past it.
            local value = effect.value
            if counter and counter.cap then
                value = math.min(value, math.max(0, counter.cap - P:Counter(effect.acct, pKey)))
            end
            move(effect.acct, value)
        elseif effect.k == "reset" and counter then
            move(effect.acct, -P:Counter(effect.acct, pKey))
        elseif effect.k == "charge" and counter and (response.plus or not bonus) then
            -- A bonus account is charged only when the winning answer used it (karma: lose half).
            move(effect.acct, -LR:CounterCharge(effect, P:Counter(effect.acct, pKey), response))
        elseif effect.k == "bottom" and response.plus and award then
            -- When the answer is one that counts: an off spec roll moves nobody.
            local queue = LR:Queue(effect.acct, rule)
            local moved = queue and P:QueueBottom(effect.acct, pKey, P:RaidKeys(), queue.frozen)
            if moved then
                award.queue = award.queue or {}
                award.queue[#award.queue + 1] = moved
            end
        end
    end
    return made
end

-- An officer's side: the raid's master looter, who is no officer, gave an item to `player` for the
-- answer `key`. This client makes the counter entries that award makes, by its own rule in force and its
-- own figures, and tells the guild, as it would for an award of its own; the entries carry the award's
-- name, so several officers in the raid add up to one. Read from the raid's master looter alone, and
-- only for a raider and an answer this client knows. Queues are not moved from here.
function LootMaster:OnWonMessage(rest, sender)
    if self:IsMasterLooter() or not GuildOS:IsOfficer() or not self:IsFromMasterLooter(sender) then return end
    -- An officer's own award reaches the guild by the officers' sync: nothing to do for it here.
    if GuildOS:IsOfficerByName(sender) then return end
    local P = GuildOS.Points
    if not (P and P.GetDB and P:GetDB()) or #rest > 120 then return end
    local sid, itemId, key, player = rest:match("^(%x+)|(%d+)|([A-Z0-9]+)|([^|]+)$")
    if not sid or #sid > 8 or #itemId > 9 or #key > 8 then return end
    -- Only for the roll this client heard that master looter announce, and once: a WON for a roll
    -- that never was, or the same one again under another id, would write the guild's counters at will.
    local heard = self.heard
    if not (heard and heard.sid == sid and heard.sender == sender) or heard.won then return end
    heard.won = true
    local name = self:RaidRollerName(player)
    if not name then return end
    local rule = GuildOS.LootRule:Active()
    local response = GuildOS.LootRule:Response(key, rule)
    if not response then return end
    local pKey = GuildOS:GetPlayerKey(name)
    self:CounterEffects(rule, response, pKey, self:AwardOp(sid, tonumber(itemId), pKey), nil)
end

----------------------------------------------------------------------
-- The record of the award being made (issue #336): the rule, the candidates in its order with what
-- each criterion compared, and what decided. Built before the award changes any account, so the
-- figures are the ones the order was read from.
----------------------------------------------------------------------
function LootMaster:AwardWhy(playerName, rule, free)
    local LR = GuildOS.LootRule
    local loot = self.activeLoot or {}
    local sorted = loot.sortedResults
    if not sorted then
        -- Given before the roll ended, or with no roll at all: whoever has answered so far.
        sorted = {}
        for _, r in pairs(self.rolls) do
            if r.rollType ~= "PASS" then sorted[#sorted + 1] = r end
        end
        LR:Sort(sorted, rule)
    end
    local decidedBy = free and "ml" or LR:WhyDecided(playerName, sorted, rule)
    -- A council's vote: awarding ends it, and the record keeps the votes whoever decided in the end.
    local votes
    local Council, session = GuildOS.LootCouncil, loot.council
    if Council and session and not free then
        if session.open then Council:Close("ml") end
        decidedBy, votes = Council:DecidedBy(session, playerName), Council:Record(session)
    end
    return LR:Why({
        rule = rule, ruleAt = loot.ruleAt or LR:Stamp(), winner = playerName,
        sorted = free and {} or sorted, decidedBy = decidedBy,
        exception = loot.exception and LR:ExceptionLabel(loot.exception) or nil, votes = votes,
    })
end

----------------------------------------------------------------------
-- Undo (issue #294): the last award, taken back. The item is no longer anybody's in the loot
-- history (here and, by the UNDO message, on the other officers' clients), the points it cost go
-- back, the +1 it counted comes off (issue #334), and a trade not yet made is dropped. Officer only;
-- one award at a time, newest first.
----------------------------------------------------------------------
local UNDO_MATCH_WINDOW = 600   -- seconds: a peer recorded the award on its own clock

-- Forget a recorded award: the newest entry for this player and item within the window.
local function forgetAward(player, itemId, at)
    local history = GuildOS.db.lootHistory or {}
    for i, e in ipairs(history) do
        local id = tonumber(e.itemLink and e.itemLink:match("item:(%d+)")) or tonumber(e.itemId)
        if e.fromML and e.player == player and id == itemId
            and math.abs((tonumber(e.timestamp) or 0) - at) <= UNDO_MATCH_WINDOW then
            table.remove(history, i)
            return true
        end
    end
    return false
end
LootMaster.ForgetAward = forgetAward

-- The newest award not undone yet, and its place in the log.
-- Looked for in the active core's log and in the log of the core this client last awarded in: an item
-- given in the core it was announced under, after another became the raid's, is still the last award.
function LootMaster:LastAward()
    local CM = GuildOS.CoreManager
    local best
    local function look(history)
        for _, a in ipairs(history or {}) do
            if not a.undone then
                if not best or (a.timestamp or 0) > (best.timestamp or 0) then best = a end
                return
            end
        end
    end
    if CM and self.lastAwardCore ~= nil then look(CM:GetAwardHistory(self.lastAwardCore)) end
    look(CM and CM:GetAwardHistory() or (GuildOS.db.lootMaster and GuildOS.db.lootMaster.awardHistory))
    return best
end

-- Returns the award taken back, or nil and why.
function LootMaster:UndoLastAward()
    if not GuildOS:IsOfficer() then return nil, L["Only an officer can undo an award."] end
    local award = self:LastAward()
    if not award then return nil, L["No award to undo."] end
    award.undone = true
    forgetAward(award.player, award.itemId, award.timestamp)
    -- Into the accounts of the core the award was made in (issue #338), whatever core is the raid's now.
    local function giveBack()
        -- Given back as it was taken: never held to a cap, and off the GP in EPGP (issues #309, #319).
        local undoLabel = L["Undo: "] .. (GuildOS.Compat.GetItemInfo(award.link) or award.link)
        if award.charged and award.charged > 0 and award.chargedKey and GuildOS.Points then
            GuildOS.Points:Refund(award.chargedKey, award.charged, undoLabel)
        end
        -- And what each roller paid to enter the roll.
        for _, paid in ipairs(GuildOS.Points and award.paid or {}) do
            GuildOS.Points:Refund(paid.key, paid.amount, undoLabel)
        end
        -- And the +1 it counted (issue #334), off the night it was added in.
        for _, plus in ipairs(GuildOS.Points and award.plus or {}) do
            GuildOS.Points:AddCounter(plus.acct, plus.key, -plus.value, plus.reset, plus.per)
        end
        -- And what it shared among the raid (zero-sum) and the place it took in a queue (issue #337).
        if GuildOS.Points and award.split then GuildOS.Points:UndoSplit(award.split, undoLabel) end
        for i = #(GuildOS.Points and award.queue or {}), 1, -1 do
            GuildOS.Points:QueueUndo(award.queue[i])
        end
        -- A client from before EPGP's two sides reads what an undo gives back as EP earned, where it
        -- comes off the GP: the snapshot sets it right there, as it does after a decay.
        if GuildOS.Points and GuildOS.Points:GetMode() == "epgp" and (award.charged or award.paid or award.split) then
            GuildOS.Points:BroadcastSnapshot()
        end
    end
    if GuildOS.Points and GuildOS.Points.InCore then GuildOS.Points:InCore(award.core, giveBack) else giveBack() end
    for i = #(self.pendingTrades or {}), 1, -1 do
        local t = self.pendingTrades[i]
        if t.player == award.player and t.itemId == award.itemId then
            table.remove(self.pendingTrades, i)
            break
        end
    end
    self:SafeSendAddon(LootMaster.PREFIX, string.format("UNDO|%s|%d|%d", award.player, award.itemId, award.timestamp), "RAID")
    self:SafeSendChat(string.format(L["[Loot] Award of %s to %s undone"], award.link, award.player), "RAID")
    return award
end

----------------------------------------------------------------------
-- Trade-based loot delivery (Gargul-style)
----------------------------------------------------------------------

-- Queue an item to be traded to a player
function LootMaster:QueueForTrade(playerName, itemLink, itemId)
    table.insert(self.pendingTrades, {
        player = playerName,
        link = itemLink,
        itemId = itemId,
        timestamp = GetServerTime(),
    })
    GuildOS:Print(string.format(L["|cffFFFF00Trade queued:|r %s for %s. Open trade with them."], itemLink, playerName))
end

-- Find an item in bags by itemId
function LootMaster:FindItemInBags(itemId)
    for bag = 0, 4 do
        for slot = 1, GuildOS.Compat.GetContainerNumSlots(bag) do
            local info = GuildOS.Compat.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId then
                return bag, slot
            end
        end
    end
    return nil, nil
end

-- When trade window opens, try to auto-add pending items
function LootMaster:OnTradeShow()
    local tradeName = UnitName("NPC") or GetUnitName("NPC", false)
    if GuildOS.Compat.IsSecret(tradeName) then return end  -- who the trade is with cannot be read
    if not tradeName then
        -- Try TradeFrame target
        tradeName = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
        if GuildOS.Compat.IsSecret(tradeName) then return end
    end
    if not tradeName or tradeName == "" then return end

    local itemsAdded = 0
    local tradeSlot = 1

    for i = #self.pendingTrades, 1, -1 do
        local pending = self.pendingTrades[i]
        if pending.player == tradeName then
            local bag, slot = self:FindItemInBags(pending.itemId)
            if bag and slot and tradeSlot <= 6 then
                -- Place item in trade window
                GuildOS.Compat.UseContainerItem(bag, slot)
                GuildOS:Print(string.format(L["|cff00ff00Auto-added:|r %s to trade."], pending.link))
                pending.addedToTrade = true
                itemsAdded = itemsAdded + 1
                tradeSlot = tradeSlot + 1
            end
        end
    end

    if itemsAdded > 0 then
        GuildOS:Print(string.format(L["%d item(s) added to trade with %s."], itemsAdded, tradeName))
    end
end

-- When trade completes, mark pending items as received
function LootMaster:OnTradeAcceptUpdate(playerAccepted, targetAccepted)
    if playerAccepted == 1 and targetAccepted == 1 then
        local tradeName = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
        if not tradeName then return end

        for i = #self.pendingTrades, 1, -1 do
            local pending = self.pendingTrades[i]
            if pending.player == tradeName and pending.addedToTrade then
                -- Mark as received in award history
                local _ah = GuildOS.CoreManager and GuildOS.CoreManager:GetAwardHistory()
                            or (GuildOS.db.lootMaster and GuildOS.db.lootMaster.awardHistory) or {}
                for _, award in ipairs(_ah) do
                    if award.itemId == pending.itemId
                        and award.player == pending.player
                        and not award.received then
                        award.received = true
                        break
                    end
                end
                GuildOS:Print(string.format(L["|cff00ff00Trade complete:|r %s delivered to %s."], pending.link, pending.player))
                table.remove(self.pendingTrades, i)
            end
        end
    end
end

-- Get pending trades (for UI display)
function LootMaster:GetPendingTrades()
    return self.pendingTrades
end

----------------------------------------------------------------------
-- Schedule RAID_WARNING countdown messages at key thresholds
-- so the raid knows when time is about to run out.
-- Only the ML sends these (called from DoNormalAnnounce/StartRestrictedRoll).
----------------------------------------------------------------------
function LootMaster:ScheduleCountdownWarnings()
    -- WoW: Forever drops these timer lines (issue #63); the raiders' popup has its own bar and
    -- the loot master's frame shows the seconds left.
    if GuildOS.Compat.NeedsClick() then return end
    local dur = self:RollTime()
    local sid = self.activeLoot and self.activeLoot.sid   -- the warnings are this roll's alone
    local warnings = { 10, 5, 3, 2, 1 }
    for _, t in ipairs(warnings) do
        if dur > t then
            local secs = t  -- capture for closure
            C_Timer.After(dur - secs, function()
                if LootMaster.activeLoot and LootMaster.activeLoot.sid == sid and not LootMaster.activeLoot.ended then
                    LootMaster:SafeSendChat(
                        L["[Roll] "] .. string.format(secs == 1 and L["%d second!"] or L["%d seconds!"], secs),
                        "RAID_WARNING")
                end
            end)
        end
    end
end

----------------------------------------------------------------------
-- Cancel current rolling session
----------------------------------------------------------------------
function LootMaster:CancelRolling()
    self:StopListeningForRolls()
    self.restrictedRollers = nil
    self:StopRollTimer()
    if self.activeLoot then
        -- A council's vote on it (issue #336) is over too.
        if self.activeLoot.council and GuildOS.LootCouncil then GuildOS.LootCouncil:Close("cancel") end
        self:SafeSendChat(L["[Loot] Roll cancelled: "] .. self.activeLoot.link, "RAID")
        self.activeLoot.delivered = true
    end
    self.activeLoot = nil
    self.rolls = {}

    if self.rollFrame and self.rollFrame:IsShown() then
        self:RefreshRollFrame()
    end
end

----------------------------------------------------------------------
-- Raider: perform /roll (MS = 1-100, OS = 1-99).
-- The ML captures the result via CHAT_MSG_SYSTEM — no addon comm needed.
----------------------------------------------------------------------
function LootMaster:SendMyRoll(rollType)
    if rollType == "MS" then
        RandomRoll(1, 100)
    elseif rollType == "OS" then
        RandomRoll(1, 99)
    end
    -- PASS: nothing to send — simply not rolling is sufficient
end

----------------------------------------------------------------------
-- UI: Roll popup for raiders — shown on ANNOUNCE (GuildOS ML session only).
-- Displays the item link, the local player's own prio/wishlist
-- position, and the full priority list so everyone can see who
-- has priority without having to ask.
-- `ask` (issue #334): what the loot master's ASK said of the rule, when
-- one came with the announce. The buttons are then the rule's, and a
-- click answers by the addon (SendAnswer). Without it (a loot master on
-- a version from before, or the settings' test) the buttons are MS, OS
-- and Pass, by /roll, as always.
----------------------------------------------------------------------
-- An edit box in the loot windows' own look.
local function lootEditBox(parent, width, numeric, maxLetters)
    local C = GuildOS.Colors
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, 22)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    box:SetBackdropColor(0.05, 0.05, 0.066, 1)
    box:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 0.5)
    GuildOS:ApplyFont(box, 11)
    box:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    box:SetAutoFocus(false)
    box:SetNumeric(numeric)
    box:SetMaxLetters(maxLetters)
    box:SetTextInsets(4, 4, 0, 0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- The rule's buttons at the foot of the roll popup, a box for the bid when an answer asks for one and
-- one for the note when an answer needs it. Returns how much taller than the MS / OS / Pass row they
-- are, for the popup to grow by.
function LootMaster:BuildAnswerControls(f, ask, itemLink, width)
    local C, UI = GuildOS.Colors, GuildOS.UI
    local MARGIN, GAP, ROW, FOOT = 15, 6, 30, 12
    local bidBox, noteBox, replyText

    local function label(text, x, y)
        local t = f:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(t, 10)
        t:SetPoint("BOTTOMLEFT", x, y + 5)
        t:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        t:SetText(text)
        return t
    end

    local function answer(r)
        local bid = 0
        if r.ask == "bid" then
            bid = bidBox and tonumber(bidBox:GetText())
            if not bid then
                replyText:SetText(L["Type your bid first."])
                return
            end
        end
        local note = noteBox and strtrim(noteBox:GetText() or "") or ""
        if r.note and note == "" then
            GuildOS:Print(L["That answer needs a note."])
            return
        end
        LootMaster:SendAnswer(r.key, bid, note)
        if r.ask == "bid" then
            -- The popup stays: a bid may be refused, or raised.
            replyText:SetText(string.format(L["Bid of %d sent."], bid))
            return
        end
        f:Hide()
        GuildOS:Print(string.format(L["Answered |cff00ff00%s|r on %s"], r.label, itemLink or L["item"]))
    end

    -- One button an answer, then Pass.
    local buttons = {}
    for i, r in ipairs(ask.responses) do
        local b = UI:CreateButton(f, r.label, 90, 26)
        if i == 1 then b:SetBackdropColor(0.0, 0.4, 0.0, 0.6) end
        b:SetScript("OnClick", function() answer(r) end)
        buttons[#buttons + 1] = b
    end
    local passBtn = UI:CreateButton(f, L["Pass"], 90, 26)
    passBtn:SetBackdropColor(0.4, 0.0, 0.0, 0.6)
    passBtn:SetScript("OnClick", function()
        LootMaster:SendAnswer("PASS", 0, "")
        f:Hide()
    end)
    buttons[#buttons + 1] = passBtn

    -- Three sit where MS, OS and Pass always did; more wrap into rows, left to right, top to bottom.
    local rows = 1
    if #buttons == 3 then
        buttons[1]:SetPoint("BOTTOMLEFT", MARGIN, FOOT)
        buttons[2]:SetPoint("BOTTOM", 0, FOOT)
        buttons[3]:SetPoint("BOTTOMRIGHT", -MARGIN, FOOT)
    else
        local rowOf, xOf, x = {}, {}, MARGIN
        for i, b in ipairs(buttons) do
            local w = b:GetWidth() or 90
            if x > MARGIN and x + w > width - MARGIN then rows, x = rows + 1, MARGIN end
            rowOf[i], xOf[i] = rows, x
            x = x + w + GAP
        end
        for i, b in ipairs(buttons) do
            b:SetPoint("BOTTOMLEFT", xOf[i], FOOT + (rows - rowOf[i]) * ROW)
        end
    end

    local y = FOOT + rows * ROW
    if ask.bids then
        label(string.format(L["Your bid (from %d):"], ask.min), MARGIN, y)
        bidBox = lootEditBox(f, 70, true, 7)
        bidBox:SetPoint("BOTTOMLEFT", 150, y)
        -- Open bids show the best one so far; sealed ones are nobody's to see.
        if not ask.sealed then
            f.highText = label(L["Highest bid: none yet"], 230, y)
        else
            label(L["Sealed: only the loot master's addon reads it."], 230, y)
        end
        y = y + ROW
    end
    for _, r in ipairs(ask.responses) do
        if r.note and not noteBox then
            label(L["Note:"], MARGIN, y)
            noteBox = lootEditBox(f, 240, false, NOTE_MAX)
            noteBox:SetPoint("BOTTOMLEFT", 70, y)
            y = y + ROW
        end
    end
    if ask.bids then
        replyText = label("", MARGIN, y - 5)
        f.replyText = replyText
        y = y + 16
    end
    return math.max(0, y - (FOOT + ROW))
end

function LootMaster:ShowRollPopup(itemLink, duration, itemId, ask)
    local C      = GuildOS.Colors
    local myName = GuildOS.Compat.PlayerName()

    if self.rollPopup then
        self.rollPopup:Hide()
    end

    ----------------------------------------------------------------
    -- Build combined priority list: officer prios first, then wishlist
    ----------------------------------------------------------------
    local entries  = {}
    local entrySet = {}  -- track names already added (deduplicate)

    -- 1. Officer prios (from db.lootPrios)
    if itemId and itemId > 0 and GuildOS.db and GuildOS.db.lootPrios then
        local prioList = GuildOS.db.lootPrios[itemId]
        if prioList then
            for idx, e in ipairs(prioList) do
                local key = strlower(e.name or "")
                if key ~= "" and not entrySet[key] then
                    table.insert(entries, {
                        name    = e.name,
                        class   = e.class or "UNKNOWN",
                        typeStr = L["PRIO"],
                        typeCat = "prio",
                        order   = idx,
                    })
                    entrySet[key] = true
                end
            end
        end
    end

    -- 2. Wishlist entries (not already covered by an officer prio)
    if itemId and itemId > 0 and GuildOS.Wishlist then
        local interest = GuildOS.Wishlist:GetItemInterest(itemId)
        if interest then
            for _, e in ipairs(interest) do
                local key = strlower(e.name or "")
                if key ~= "" and not entrySet[key] then
                    table.insert(entries, {
                        name    = e.name,
                        class   = e.class or "UNKNOWN",
                        typeStr = L["WISH"],
                        typeCat = "wishlist",
                        order   = e.order or 999,
                    })
                    entrySet[key] = true
                end
            end
        end
    end

    -- Annotate with in-group status and update class from live unit data
    local inGroup    = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name, _, classFile = GuildOS.Compat.UnitIdentity(unit)
        if name then
            inGroup[strlower(name)] = classFile or "UNKNOWN"
        end
    end
    -- Always include self (covers solo testing and the local player's row highlight)
    inGroup[strlower(myName)] = select(2, UnitClass("player")) or "UNKNOWN"

    for _, e in ipairs(entries) do
        local key = strlower(e.name)
        e.inRaid = inGroup[key] ~= nil
        if inGroup[key] then
            e.class = inGroup[key]  -- prefer live unit class over stored value
        end
    end

    ----------------------------------------------------------------
    -- Calculate frame dimensions
    ----------------------------------------------------------------
    local MAX_VISIBLE = 10
    local numEntries  = #entries
    local visCount    = math.min(numEntries, MAX_VISIBLE)
    local ROW_H       = 20

    -- list area: column-header row + entry rows + optional overflow label
    local listArea
    if numEntries > 0 then
        listArea = 20 + visCount * ROW_H
        if numEntries > MAX_VISIBLE then listArea = listArea + 16 end
    else
        listArea = 22  -- "no wishlist data" label
    end

    local FRAME_W = 360
    local TOP_H   = 68   -- title + item link + status
    local BTN_H   = 42   -- buttons + timer bar
    local FRAME_H = math.max(120, TOP_H + listArea + BTN_H + 10)

    ----------------------------------------------------------------
    -- Main frame
    ----------------------------------------------------------------
    local f = CreateFrame("Frame", "GuildOSRollPopup", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.082, 0.082, 0.105, 0.95)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    GuildOS.UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(title, 12)
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText(L["Guild OS Loot Master"])

    -- Item link
    local itemText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(itemText, 11)
    itemText:SetPoint("TOP", 0, -26)
    itemText:SetText(itemLink or L["Unknown Item"])

    -- Player's own prio / wishlist status
    local tmbText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(tmbText, 10)
    tmbText:SetPoint("TOP", 0, -44)
    tmbText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    if itemId and itemId > 0 then
        local myPrioOrder = nil
        if GuildOS.db and GuildOS.db.lootPrios and GuildOS.db.lootPrios[itemId] then
            for idx, e in ipairs(GuildOS.db.lootPrios[itemId]) do
                if strlower(e.name or "") == strlower(myName) then
                    myPrioOrder = idx
                    break
                end
            end
        end

        if myPrioOrder then
            tmbText:SetText(format(L["|cffFFD700[OFFICIAL PRIO #%d]|r"], myPrioOrder))
        else
            local interest = GuildOS.Wishlist and GuildOS.Wishlist:GetItemInterest(itemId)
            local myEntry  = nil
            if interest then
                for _, e in ipairs(interest) do
                    if strlower(e.name) == strlower(myName) then
                        myEntry = e
                        break
                    end
                end
            end
            if myEntry then
                tmbText:SetText(L["|cff4CB8FFWishlist #"] .. myEntry.order .. "|r")
            else
                tmbText:SetText(L["|cff666666Not on your wishlist|r"])
            end
        end
    end

    ----------------------------------------------------------------
    -- Priority list
    ----------------------------------------------------------------
    local listY = -(TOP_H)

    -- Thin separator above list
    local sep1 = f:CreateTexture(nil, "ARTWORK")
    sep1:SetTexture("Interface\\Buttons\\WHITE8x8")
    sep1:SetHeight(1)
    sep1:SetPoint("TOPLEFT",  8, listY)
    sep1:SetPoint("TOPRIGHT", -8, listY)
    sep1:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.35)
    listY = listY - 2

    if numEntries > 0 then
        -- Column headers
        local function MakeHdr(lbl, xOff)
            local h = f:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(h, 8)
            h:SetPoint("TOPLEFT", xOff, listY - 2)
            h:SetTextColor(0.5, 0.5, 0.5)
            h:SetText(lbl)
        end
        MakeHdr("#",            12)
        MakeHdr(L["TYPE"],      26)
        MakeHdr(L["ORD"],       68)
        MakeHdr(L["PLAYER"],    98)
        MakeHdr(L["ATT%"],     234)
        MakeHdr(L["RECV"],     275)
        MakeHdr(L["RAID"],     310)
        listY = listY - 18

        -- Entry rows
        for idx = 1, visCount do
            local e    = entries[idx]
            local isMe = strlower(e.name) == strlower(myName)

            local row = CreateFrame("Frame", nil, f, "BackdropTemplate")
            row:SetSize(FRAME_W - 16, ROW_H)
            row:SetPoint("TOPLEFT", 8, listY)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

            if isMe then
                row:SetBackdropColor(0.08, 0.22, 0.08, 0.9)
            else
                local bg   = (idx % 2 == 1) and C.row1 or C.row2
                local bgA  = e.inRaid and (bg.a or 0.6) or ((bg.a or 0.6) * 0.4)
                row:SetBackdropColor(bg.r, bg.g, bg.b, bgA)
            end

            -- # (index)
            local idxT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(idxT, 9)
            idxT:SetPoint("LEFT", 4, 0)
            idxT:SetTextColor(
                e.inRaid and C.gold.r or 0.35,
                e.inRaid and C.gold.g or 0.35,
                e.inRaid and C.gold.b or 0.35)
            idxT:SetText(idx)

            -- TYPE (PRIO / WISH)
            local typeT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(typeT, 8)
            typeT:SetPoint("LEFT", 18, 0)
            local tc = e.typeCat == "prio" and C.accent or C.gold
            typeT:SetTextColor(
                e.inRaid and tc.r or tc.r * 0.5,
                e.inRaid and tc.g or tc.g * 0.5,
                e.inRaid and tc.b or tc.b * 0.5)
            typeT:SetText(e.typeStr)

            -- Order (#N)
            local ordT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(ordT, 8)
            ordT:SetPoint("LEFT", 60, 0)
            ordT:SetTextColor(
                e.inRaid and 0.65 or 0.3,
                e.inRaid and 0.65 or 0.3,
                e.inRaid and 0.65 or 0.3)
            ordT:SetText("#" .. e.order)

            -- Name (class-colored when in group / is self)
            local nameT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(nameT, 10)
            nameT:SetPoint("LEFT", 92, 0)
            nameT:SetWidth(134)
            if e.inRaid or isMe then
                local cr, cg, cb = GuildOS:GetClassColor(e.class)
                nameT:SetTextColor(cr, cg, cb)
            else
                nameT:SetTextColor(0.4, 0.4, 0.4)
            end
            nameT:SetText(e.name)

            -- ATT% (25-man attendance)
            local attCtx = self:GetPlayerContext(e.name)
            local attT   = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(attT, 9)
            attT:SetPoint("LEFT", 228, 0)
            attT:SetWidth(40)
            attT:SetJustifyH("CENTER")
            if attCtx.att25 >= 60 then
                attT:SetTextColor(0.3, 1.0, 0.3)
            elseif attCtx.att25 >= 40 then
                attT:SetTextColor(1.0, 1.0, 0.3)
            else
                attT:SetTextColor(1.0, 0.3, 0.3)
            end
            attT:SetText(attCtx.att25 .. "%")

            -- RECV (items received this lockout)
            local recvT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(recvT, 9)
            recvT:SetPoint("LEFT", 270, 0)
            recvT:SetWidth(32)
            recvT:SetJustifyH("CENTER")
            if attCtx.recvThisLockout == 0 then
                recvT:SetTextColor(0.4, 0.4, 0.4)
            elseif attCtx.recvThisLockout == 1 then
                recvT:SetTextColor(1.0, 1.0, 0.3)
            else
                recvT:SetTextColor(1.0, 0.3, 0.3)
            end
            recvT:SetText(tostring(attCtx.recvThisLockout))

            -- IN RAID indicator
            local raidT = row:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(raidT, 9)
            raidT:SetPoint("LEFT", 306, 0)
            if e.inRaid then
                raidT:SetTextColor(0.3, 1.0, 0.3)
                raidT:SetText(L["YES"])
            else
                raidT:SetTextColor(0.4, 0.4, 0.4)
                raidT:SetText("-")
            end

            listY = listY - ROW_H
        end

        -- Overflow label when list is clipped
        if numEntries > MAX_VISIBLE then
            local moreT = f:CreateFontString(nil, "OVERLAY")
            GuildOS:ApplyFont(moreT, 9)
            moreT:SetPoint("TOPLEFT", 12, listY - 2)
            moreT:SetTextColor(0.5, 0.5, 0.5)
            moreT:SetText(format(L["+ %d more interested"], numEntries - MAX_VISIBLE))
        end
    else
        -- No wishlist/prio data for this item
        local noDataT = f:CreateFontString(nil, "OVERLAY")
        GuildOS:ApplyFont(noDataT, 9)
        noDataT:SetPoint("TOPLEFT", 12, listY - 4)
        noDataT:SetTextColor(0.5, 0.5, 0.5)
        noDataT:SetText(L["No wishlist data for this item."])
    end

    ----------------------------------------------------------------
    -- Roll buttons (MS / OS / Pass)
    ----------------------------------------------------------------
    local UI = GuildOS.UI
    if ask then
        -- The rule's own buttons, answered by the addon (issue #334).
        f:SetHeight(FRAME_H + self:BuildAnswerControls(f, ask, itemLink, FRAME_W))
    else
        local msBtn = UI:CreateButton(f, "MS", 90, 26)
        msBtn:SetPoint("BOTTOMLEFT", 15, 12)
        msBtn:SetBackdropColor(0.0, 0.4, 0.0, 0.6)
        msBtn:SetScript("OnClick", function()
            RandomRoll(1, 100)
            f:Hide()
            GuildOS:Print(L["Rolled |cff00ff00MS|r on "] .. (itemLink or L["item"]) .. " — /roll 1-100")
        end)

        local osBtn = UI:CreateButton(f, "OS", 90, 26)
        osBtn:SetPoint("BOTTOM", 0, 12)
        osBtn:SetScript("OnClick", function()
            RandomRoll(1, 99)
            f:Hide()
            GuildOS:Print(L["Rolled |cffFFFF00OS|r on "] .. (itemLink or L["item"]) .. " — /roll 1-99")
        end)

        local passBtn = UI:CreateButton(f, L["Pass"], 90, 26)
        passBtn:SetPoint("BOTTOMRIGHT", -15, 12)
        passBtn:SetBackdropColor(0.4, 0.0, 0.0, 0.6)
        passBtn:SetScript("OnClick", function()
            f:Hide()
        end)
    end

    ----------------------------------------------------------------
    -- Timer countdown bar + 5-second warning
    ----------------------------------------------------------------
    local timerBar = CreateFrame("StatusBar", nil, f)
    timerBar:SetSize(FRAME_W - 20, 4)
    timerBar:SetPoint("BOTTOM", 0, 6)
    timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    timerBar:SetStatusBarColor(C.accent.r, C.accent.g, C.accent.b, 0.8)
    timerBar:SetMinMaxValues(0, duration)
    timerBar:SetValue(duration)

    -- Warning label (hidden until last 5s)
    local warnText = f:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(warnText, 13)
    warnText:SetPoint("BOTTOM", 0, 14)
    warnText:SetTextColor(1.0, 0.2, 0.2)
    warnText:Hide()

    local elapsed     = 0
    local warnFired   = false
    local warnFlash   = 0
    local ticker = C_Timer.NewTicker(0.1, function()
        elapsed   = elapsed + 0.1
        local remaining = duration - elapsed
        if remaining <= 0 then
            f:Hide()
            return
        end
        timerBar:SetValue(remaining)

        -- Switch bar to red in last 5s
        if remaining <= 5 then
            timerBar:SetStatusBarColor(1.0, 0.15, 0.15, 0.9)

            -- Play sound once when we cross 5s
            if not warnFired then
                warnFired = true
                PlaySound(SOUNDKIT and SOUNDKIT.IG_ABILITY_ICON_DROP or 1304)
            end

            -- Flash "X segundos!" label
            warnFlash = warnFlash + 0.1
            local secs = math.ceil(remaining)
            warnText:SetText(secs .. "s!")
            warnText:Show()
            -- Pulse alpha: 0.5s cycle
            local alpha = 0.6 + 0.4 * math.abs(math.sin(warnFlash * math.pi * 2))
            warnText:SetAlpha(alpha)
        end
    end)

    f:SetScript("OnHide", function()
        ticker:Cancel()
        LootMaster.testMode = false
    end)

    f:Show()
    self.rollPopup = f
end

----------------------------------------------------------------------
-- Set active loot for direct award (without starting a roll session)
----------------------------------------------------------------------
function LootMaster:SetActiveLoot(link, slot, itemId)
    self.activeLoot = {
        core      = self:ActiveCore(),
        link      = link,
        slot      = slot,
        itemId    = itemId,
        startTime = GetServerTime(),
        endTime   = GetServerTime(),
    }
    self.rolls = {}
end

----------------------------------------------------------------------
-- The master looter's loot table (issue #346): the boss's items on the left, each with where it
-- stands, and on the right the candidates of the one picked in the rule's order, why each is where
-- the rule puts them, the decision in a sentence, and Award / End now / Disenchant / Cancel; under
-- the items, what was given out tonight and Undo. One window, built once, for the loot window that
-- opens on a boss (ShowLootFrame), a roll announced from it or from a bag (ShowRollFrame) and the
-- settings' test. It was two windows of fixed columns (the loot frame and the roll tracker).
----------------------------------------------------------------------
local TABLE_W, TABLE_H       = 800, 480
local TABLE_MIN_W, TABLE_MIN_H = 600, 360
local TABLE_LIST_W           = 214   -- the items' column
local TABLE_ROW_H            = 22
local TABLE_ITEM_H           = 34
local TABLE_PAD              = 10
local TABLE_FOOT             = 40    -- the buttons' row

-- The candidates' columns, by priority: the player, the answer and the roll stay; the rest drop.
local TABLE_COLS = {
    { key = "rank",   min = 20,  weight = 0, priority = 2 },
    { key = "name",   min = 90,  weight = 2, priority = 9, required = true },
    { key = "answer", min = 56,  weight = 1, priority = 8, required = true },
    { key = "why",    min = 110, weight = 4, priority = 6 },
    { key = "plus",   min = 30,  weight = 0, priority = 3 },
    { key = "att",    min = 40,  weight = 0, priority = 4 },
    { key = "roll",   min = 56,  weight = 1, priority = 7, required = true },
}

-- Who is in the group now, by lower-case name: their class.
local function raidMap()
    local map = {}
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name, _, classFile = GuildOS.Compat.UnitIdentity(unit)
        if name then map[strlower(name)] = classFile or "UNKNOWN" end
    end
    local me = GuildOS.Compat.PlayerName()
    if me then map[strlower(me)] = select(2, UnitClass("player")) or "UNKNOWN" end
    return map
end

-- Before a roll: who has the item on a list, in the lists' order (officer prio, then wishlist), who
-- of them is in the group, and the first of them when no one else in the group shares their place.
-- Returns the rows, the first (or nil) and how many share the first place.
function LootMaster:InterestFor(itemId)
    local rows, top, tied = {}, nil, 0
    local interest = itemId and GuildOS.Wishlist and GuildOS.Wishlist:GetItemInterest(itemId)
    if not interest then return rows, nil, 0 end
    local here = raidMap()
    for _, e in ipairs(interest) do
        if e.type ~= "received" then
            local row = {
                name = e.name, class = here[strlower(e.name or "")] or e.class, inRaid = here[strlower(e.name or "")] ~= nil,
                prioOrder = e.type == "prio" and e.order or nil,
                wishlist = e.type ~= "prio" and { order = e.order } or nil, listType = e.type, order = e.order,
            }
            rows[#rows + 1] = row
            if row.inRaid and not top then top = row end
        end
    end
    if top then
        for _, r in ipairs(rows) do
            if r.inRaid and r.listType == top.listType and r.order == top.order then tied = tied + 1 end
        end
    end
    return rows, top, tied
end

-- The candidates the table shows for `item`: the answers of its roll in the rule's order (a pass
-- last), or before its roll who has it on a list. Returns the rows, "rolls" or "lists", and the
-- one the rule puts first (nil when nobody asked, or when the lists tie).
function LootMaster:TableCandidates(item)
    local loot = self.activeLoot
    if loot and item and loot.link == item.link and not loot.delivered then
        local sorted = {}
        for _, r in pairs(self.rolls) do sorted[#sorted + 1] = r end
        GuildOS.LootRule:Sort(sorted, self:Rule())
        local first = sorted[1]
        if first and first.rollType == "PASS" then first = nil end
        return sorted, "rolls", first
    end
    local itemId = item and tonumber(tostring(item.link):match("item:(%d+)"))
    local rows, top, tied = self:InterestFor(itemId)
    return rows, "lists", tied == 1 and top or nil, tied
end

local function tableText(parent, size, col)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GuildOS:ApplyFont(fs, size or 11)
    col = col or GuildOS.Colors.text
    fs:SetTextColor(col.r, col.g, col.b)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    return fs
end

function LootMaster:BuildLootTable()
    local C, UI = GuildOS.Colors, GuildOS.UI
    local LR = GuildOS.LootRule
    local f = CreateFrame("Frame", "GuildOSLootTable", UIParent, "BackdropTemplate")
    f:SetSize(TABLE_W, TABLE_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(TABLE_MIN_W, TABLE_MIN_H) elseif f.SetMinResize then f:SetMinResize(TABLE_MIN_W, TABLE_MIN_H) end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    -- Title: what is being given, by which rule, and the clock.
    f.title = UI:CreateTitle(f, L["Loot table"], 14)
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.ruleText = UI:CreateText(f, "", 10, C.labelDim.r, C.labelDim.g, C.labelDim.b)
    f.ruleText:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
    f.timerText = UI:CreateText(f, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.timerText:SetPoint("TOPRIGHT", -34, -12)
    local close = UI:CreateCloseButton(f)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)
    local titleSep = UI:CreateSeparator(f)
    titleSep:SetPoint("TOPLEFT", 8, -32)
    titleSep:SetPoint("TOPRIGHT", -8, -32)

    -- The resize grip.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    local gripMark = grip:CreateTexture(nil, "OVERLAY")
    gripMark:SetTexture("Interface\\Buttons\\WHITE8x8")
    gripMark:SetSize(8, 1)
    gripMark:SetPoint("BOTTOMRIGHT", -2, 3)
    gripMark:SetVertexColor(C.lineHi.r, C.lineHi.g, C.lineHi.b, 1)

    -- ── Left: the boss's items, then what was given tonight ──────────
    local left = CreateFrame("Frame", nil, f)
    left:SetPoint("TOPLEFT", TABLE_PAD, -40)
    left:SetPoint("BOTTOMLEFT", TABLE_PAD, TABLE_PAD)
    left:SetWidth(TABLE_LIST_W)
    f.left = left
    local itemsHdr = UI:CreateHeaderText(left, L["BOSS ITEMS"], 10)
    itemsHdr:SetPoint("TOPLEFT", 0, 0)
    f.itemsHdr = itemsHdr
    f.itemRows = {}
    local nightHdr = UI:CreateHeaderText(left, L["DELIVERED TONIGHT"], 10)
    f.nightHdr = nightHdr
    f.nightLines = {}
    local undoBtn = UI:CreateButton(left, L["Undo last award"], TABLE_LIST_W, 22)
    undoBtn:SetPoint("BOTTOMLEFT", 0, 0)
    undoBtn:SetScript("OnClick", function()
        local award, why = LootMaster:UndoLastAward()
        f.status:SetText(award and string.format(L["|cffFFD700Undone:|r %s"], award.link) or ("|cffFF4444" .. why .. "|r"))
        LootMaster:RefreshRollFrame()
    end)
    f.undoBtn = undoBtn
    local vDiv = f:CreateTexture(nil, "ARTWORK")
    vDiv:SetTexture("Interface\\Buttons\\WHITE8x8")
    vDiv:SetWidth(1)
    vDiv:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    vDiv:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 6, 0)
    vDiv:SetVertexColor(C.line.r, C.line.g, C.line.b, 1)

    -- ── Right: the item picked ───────────────────────────────────────
    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)
    right:SetPoint("BOTTOMRIGHT", -TABLE_PAD, TABLE_PAD)
    f.right = right
    f.itemText = tableText(right, 12)
    f.itemText:SetPoint("TOPLEFT", 0, 0)
    f.itemText:SetPoint("RIGHT", right, "RIGHT", 0, 0)

    -- Answer for someone with no GuildOS (issue #334): the name, the answer, the bid when it asks for
    -- one; and the loot master's own answer, by the rule's first two answers.
    local strip = CreateFrame("Frame", nil, right)
    strip:SetPoint("TOPLEFT", 0, -22)
    strip:SetPoint("TOPRIGHT", 0, -22)
    strip:SetHeight(24)
    local forLabel = tableText(strip, 10, C.silver)
    forLabel:SetPoint("LEFT", 0, 0)
    forLabel:SetText(L["Answer for someone:"])
    local forBox = lootEditBox(strip, 110, false, 48)
    forBox:SetPoint("LEFT", forLabel, "RIGHT", 6, 0)
    local forAnswer = UI:CreateDropdown(strip, 90, 22)
    forAnswer:SetPoint("LEFT", forBox, "RIGHT", 6, 0)
    local forBid = lootEditBox(strip, 56, true, 7)
    forBid:SetPoint("LEFT", forAnswer, "RIGHT", 6, 0)
    local forEnter = UI:CreateButton(strip, L["Enter answer"], 100, 22)
    forEnter:SetPoint("LEFT", forBid, "RIGHT", 6, 0)
    local function entered(row, why, n)
        if not row then GuildOS:Print("|cffFF4444" .. LootMaster:WhyNot(why, n) .. "|r") end
        return row
    end
    forEnter:SetScript("OnClick", function()
        if entered(LootMaster:EnterAnswer(forBox:GetText(), forAnswer:GetValue(), tonumber(forBid:GetText()))) then
            forBox:SetText("")
        end
    end)
    local mineLabel = tableText(strip, 10, C.silver)
    mineLabel:SetText(L["Your roll:"])
    local mine = {}
    local firstAnswers = LR:Responses(self:Rule())
    for i = 1, 2 do
        local b = UI:CreateButton(strip, firstAnswers[i] and firstAnswers[i].key or "-", 44, 22)
        b.index = i
        b:SetScript("OnClick", function(self)
            local r = LR:Responses(LootMaster:Rule())[self.index]
            if r then entered(LootMaster:EnterAnswer(GuildOS.Compat.PlayerName(), r.key, tonumber(forBid:GetText()))) end
        end)
        b:SetScript("OnEnter", function(self)
            local r = LR:Responses(LootMaster:Rule())[self.index]
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(string.format(L["Your answer: %s"], LR:ResponseLabel(r)), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mine[i] = b
    end
    mine[2]:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
    mine[1]:SetPoint("RIGHT", mine[2], "LEFT", -4, 0)
    mineLabel:SetPoint("RIGHT", mine[1], "LEFT", -6, 0)
    f.strip, f.forBox, f.forAnswer, f.forBid, f.mine, f.forEnter = strip, forBox, forAnswer, forBid, mine, forEnter

    -- The candidates.
    local head = CreateFrame("Frame", nil, right)
    head:SetPoint("TOPLEFT", 0, -52)
    head:SetPoint("TOPRIGHT", 0, -52)
    head:SetHeight(18)
    f.head = head
    f.heads = {}
    local TITLES = { rank = "#", name = L["PLAYER"], answer = L["ANSWER"], why = L["WHY THEY ARE HERE"],
        plus = "+1", att = L["ATT%"], roll = L["ROLL"] }
    for _, col in ipairs(TABLE_COLS) do f.heads[col.key] = UI:CreateHeaderText(head, TITLES[col.key], 9) end
    local scroll, child = UI:CreateScrollFrame(right, "GuildOSLootTableScroll")
    scroll:SetPoint("TOPLEFT", 0, -72)
    scroll:SetPoint("BOTTOMRIGHT", -10, TABLE_FOOT + 40)
    f.scroll, f.scrollContent = scroll, child
    f.rows = {}

    -- The decision, in a sentence, before the button that carries it out.
    f.decision = UI:CreateText(right, "", 11, C.text.r, C.text.g, C.text.b)
    f.decision:SetPoint("BOTTOMLEFT", 0, TABLE_FOOT + 4)
    f.decision:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    f.decision:SetJustifyH("LEFT")
    if f.decision.SetWordWrap then f.decision:SetWordWrap(true) end
    f.status = UI:CreateText(right, "", 10, C.silver.r, C.silver.g, C.silver.b)
    f.status:SetPoint("BOTTOMLEFT", 0, TABLE_FOOT - 12)
    f.status:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    f.status:SetJustifyH("LEFT")

    -- Award · End now (or Open roll) · Disenchant · Cancel.
    local awardBtn = UI:CreateButton(right, L["Award"], 150, 26)
    UI:SetButtonVariant(awardBtn, "primary")
    awardBtn:SetPoint("BOTTOMLEFT", 0, 0)
    local endBtn = UI:CreateButton(right, L["End now"], 100, 26)
    endBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)
    endBtn:SetScript("OnClick", function()
        LootMaster:EndRolling(true)    -- a click: the winner line goes out on Forever too (#63)
        LootMaster:RefreshRollFrame()
    end)
    local openBtn = UI:CreateButton(right, L["Open Roll"], 100, 26)
    openBtn:SetPoint("LEFT", awardBtn, "RIGHT", 6, 0)
    local deBtn = UI:CreateButton(right, L["Disenchant"], 100, 26)
    deBtn:SetPoint("LEFT", endBtn, "RIGHT", 6, 0)
    local cancelBtn = UI:CreateButton(right, L["Cancel"], 80, 26)
    UI:SetButtonVariant(cancelBtn, "danger")
    cancelBtn:SetPoint("LEFT", deBtn, "RIGHT", 6, 0)
    f.awardBtn, f.endBtn, f.openBtn, f.deBtn, f.cancelBtn = awardBtn, endBtn, openBtn, deBtn, cancelBtn

    awardBtn:SetScript("OnClick", function()
        local item, who = f.selected, f.chosen
        if not (item and who) then return end
        local loot = LootMaster.activeLoot
        if not (loot and loot.link == item.link) then
            LootMaster:SetActiveLoot(item.link, item.slot, tonumber(item.link:match("item:(%d+)")))
        end
        LootMaster:AwardLoot(who)
        f.status:SetText(string.format(L["|cff4CFF4CAwarded to %s.|r"], who))
        f.picked = nil
        LootMaster:RefreshRollFrame()
    end)
    openBtn:SetScript("OnClick", function()
        local item = f.selected
        if not item then return end
        -- One roll at a time: the one that is open is ended, awarded or cancelled first.
        local open = LootMaster:OpenRoll()
        if open then
            f.status:SetText("|cffFF4444" .. L["Roll in progress: "] .. open .. "|r")
            return
        end
        LootMaster:AnnounceItem(item.link, item.slot)
        LootMaster:ShowRollFrame()
    end)
    deBtn:SetScript("OnClick", function()
        local item = f.selected
        if not item then return end
        local loot = LootMaster.activeLoot
        if not (loot and loot.link == item.link) then
            LootMaster:SetActiveLoot(item.link, item.slot, tonumber(item.link:match("item:(%d+)")))
            loot = LootMaster.activeLoot
        end
        LootMaster:SendToDisenchanter(loot.link, loot.slot, loot.itemId)
        f.status:SetText(L["|cff9966FFSent to Disenchant!|r"])
        LootMaster:RefreshRollFrame()
    end)
    -- Who disenchants is set in the Loot window's Rule tab, its one place (issue #346).
    deBtn:SetScript("OnEnter", function(self)
        local de = LootMaster:GetDisenchanter()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Send to Disenchant"], 1, 1, 1)
        if de ~= "" then
            GameTooltip:AddLine(de, 0.3, 1, 0.3)
        else
            GameTooltip:AddLine(L["No disenchanter set: Loot, Rule tab."], 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    deBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cancelBtn:SetScript("OnClick", function()
        LootMaster:CancelRolling()
        LootMaster:RefreshRollFrame()
    end)

    f:SetScript("OnHide", function()
        if f.ticker then f.ticker:Cancel(); f.ticker = nil end
        LootMaster.testMode = false
    end)
    UI:MakeResponsive(f, function() LootMaster:RefreshRollFrame() end)
    return f
end

-- The table, built the first time; the loot window, the roll tracker and the settings' test all show it.
function LootMaster:LootTable()
    if not self.lootTable then
        self.lootTable = self:BuildLootTable()
        self.lootFrame, self.rollFrame = self.lootTable, self.lootTable
    end
    return self.lootTable
end

local function showTable(self)
    local f = self:LootTable()
    f:Show()
    if not f.ticker then
        f.ticker = C_Timer.NewTicker(1, function() LootMaster:UpdateRollTimer() end)
    end
    self:RefreshRollFrame()
    return f
end

-- The boss's items, as the loot window lists them: { { slot, link, name, quality }, ... }.
function LootMaster:ShowLootFrame(items)
    self.lootItems = items or {}
    self.lootShownAt = GetServerTime()
    local f = self:LootTable()
    f.selected, f.picked = self.lootItems[1], nil
    showTable(self)
end

-- A roll announced (from the table, a bag click or the settings' test): its item joins the list.
function LootMaster:ShowRollFrame()
    local f = self:LootTable()
    local loot = self.activeLoot
    if loot then
        self.lootItems = self.lootItems or {}
        local found
        for _, item in ipairs(self.lootItems) do
            if item.link == loot.link then found = item end
        end
        if not found then
            local _, _, q = GuildOS.Compat.GetItemInfo(loot.link)
            found = { slot = loot.slot, link = loot.link, quality = q or 4 }
            table.insert(self.lootItems, found)
        end
        f.selected, f.picked = found, nil
        self.lootShownAt = self.lootShownAt or GetServerTime()
    end
    showTable(self)
end

----------------------------------------------------------------------
-- Draw the table again: the items and their state, the candidates of the item picked, the decision
-- and what the buttons do now. Every figure is the loot rule's (TableCandidates, WhyHere,
-- DecisionText); this only lays them out.
----------------------------------------------------------------------
function LootMaster:RefreshRollFrame()
    local f = self.lootTable
    if not f or not f:IsShown() then return end
    local C, UI, LR = GuildOS.Colors, GuildOS.UI, GuildOS.LootRule
    local rule = self:Rule()
    local W, H = f:GetWidth() or TABLE_W, f:GetHeight() or TABLE_H

    -- Which rule, of which core.
    local core = self.activeLoot and self.activeLoot.core or self:ActiveCore()
    f.ruleText:SetText(string.format("%s \194\183 %s", (core ~= "" and core) or L["The guild"], LR:ModelName(rule)))

    -- ── The items ───────────────────────────────────────────────────
    local items = self.lootItems or {}
    if not f.selected then f.selected = items[1] end
    f.itemsHdr:SetText(string.format(L["BOSS ITEMS (%d)"], #items))
    local y = 18
    for i, item in ipairs(items) do
        local row = f.itemRows[i]
        if not row then
            row = CreateFrame("Button", nil, f.left, "BackdropTemplate")
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            row.name = tableText(row, 11)
            row.name:SetPoint("TOPLEFT", 6, -4)
            row.name:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.state = tableText(row, 9, C.labelDim)
            row.state:SetPoint("BOTTOMLEFT", 6, 4)
            row.state:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row:SetScript("OnClick", function(self)
                f.selected, f.picked = self.item, nil
                LootMaster:RefreshRollFrame()
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:SetHyperlink(self.item.link)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.itemRows[i] = row
        end
        row.item = item
        row:SetSize(TABLE_LIST_W, TABLE_ITEM_H - 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        local qc = GuildOS.QualityColors[item.quality] or GuildOS.QualityColors[4]
        row.name:SetText(item.name or item.link)
        row.name:SetTextColor(qc.r, qc.g, qc.b)
        local state, text = self:ItemState(item)
        row.stateKey = state
        row.state:SetText(text)
        local ink = (state == "rolling" and C.gold) or (state == "awarded" and C.ok) or C.labelDim
        row.state:SetTextColor(ink.r, ink.g, ink.b)
        local on = f.selected == item
        row:SetBackdropColor(C.well.r, C.well.g, C.well.b, on and 1 or 0)
        local edge = on and C.gold or C.line
        row:SetBackdropBorderColor(edge.r, edge.g, edge.b, 1)
        row:Show()
        y = y + TABLE_ITEM_H
    end
    for i = #items + 1, #f.itemRows do f.itemRows[i]:Hide() end

    -- What was given tonight, newest first, as many as the column has room for.
    y = y + 10
    f.nightHdr:ClearAllPoints()
    f.nightHdr:SetPoint("TOPLEFT", 0, -y)
    y = y + 18
    local room = math.max(0, math.floor((H - 40 - TABLE_PAD - y - 30) / 14))
    local night = self:NightAwards(core)
    for i = 1, math.max(#f.nightLines, math.min(room, #night)) do
        local line = f.nightLines[i]
        if not line then
            line = tableText(f.left, 10, C.silver)
            f.nightLines[i] = line
        end
        local a = i <= room and night[i]
        if a then
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", 0, -(y + (i - 1) * 14))
            line:SetWidth(TABLE_LIST_W)
            line:SetText(string.format("%s \226\134\146 %s", GuildOS.Compat.GetItemInfo(a.link) or a.link or "?", a.player or "?"))
            line:Show()
        else
            line:Hide()
        end
    end
    if #night == 0 then
        local line = f.nightLines[1] or tableText(f.left, 10, C.labelDim)
        f.nightLines[1] = line
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", 0, -y)
        line:SetText(L["Nothing given yet."])
        line:Show()
    end

    -- ── The item picked ─────────────────────────────────────────────
    local item = f.selected
    f.itemText:SetText(item and item.link or L["|cff888888Select an item from the left.|r"])
    local answers = LR:Responses(rule)
    local opts = {}
    for i, r in ipairs(answers) do opts[i] = { value = r.key, text = LR:ResponseLabel(r) } end
    f.forAnswer:SetOptions(opts)
    local keep = false
    for _, o in ipairs(opts) do keep = keep or o.value == f.forAnswer:GetValue() end
    if not keep then f.forAnswer:SetValue(opts[1] and opts[1].value) end
    if LR:HasBids(rule) then f.forBid:Show() else f.forBid:Hide() end
    for i, b in ipairs(f.mine) do
        local r = answers[i]
        if r then b.label:SetText(r.key); b:Show() else b:Hide() end
    end

    local rows, mode, first, tied = self:TableCandidates(item)
    local loot = self.activeLoot
    local ours = loot and item and loot.link == item.link and not loot.delivered
    local ended = ours and loot.ended
    -- Whom the Award button gives it to: the one the master looter clicked, while they are still a
    -- candidate; else the rule's first once the answers are in, and before a roll the first on the lists.
    local picked
    for _, r in ipairs(rows) do
        if f.picked and r.name == f.picked and r.rollType ~= "PASS" then picked = r.name end
    end
    f.picked = picked
    f.chosen = picked or (mode == "lists" and first and first.name) or (ended and first and first.name) or nil

    -- The columns that fit, by priority; no "+1" where the rule keeps no counter.
    local counters = LR:Counters(rule)
    local spec = {}
    for _, col in ipairs(TABLE_COLS) do
        if not (col.key == "plus" and #counters == 0) then spec[#spec + 1] = col end
    end
    local tableW = math.max(1, W - TABLE_LIST_W - TABLE_PAD * 2 - 14 - 14)
    f.scrollContent:SetWidth(tableW)
    local layout = UI:ResolveColumns(spec, tableW, 6)
    for _, col in ipairs(TABLE_COLS) do
        local at, fs = layout.byKey[col.key], f.heads[col.key]
        fs:ClearAllPoints()
        if at and at.shown then
            fs:SetPoint("LEFT", f.head, "LEFT", at.x + 4, 0)
            fs:Show()
        else
            fs:Hide()
        end
    end
    f.layout = layout

    local sealed = LR:BidRules(rule)
    for i, r in ipairs(rows) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Button", nil, f.scrollContent, "BackdropTemplate")
            row:SetHeight(TABLE_ROW_H)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row.cells = {}
            for _, col in ipairs(TABLE_COLS) do row.cells[col.key] = tableText(row, 10) end
            row:SetScript("OnClick", function(self)
                if self.candidate and self.candidate.rollType ~= "PASS" then
                    f.picked = self.candidate.name
                    LootMaster:RefreshRollFrame()
                end
            end)
            row:SetScript("OnEnter", function(self)
                if not self.tip or #self.tip == 0 then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tip[1], 1, 1, 1)
                for n = 2, #self.tip do GameTooltip:AddLine(self.tip[n], 0.8, 0.8, 0.8) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.rows[i] = row
        end
        row.candidate = r
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * (TABLE_ROW_H + 2))
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * (TABLE_ROW_H + 2))
        local pass = r.rollType == "PASS"
        local chosen = f.chosen ~= nil and r.name == f.chosen
        local bg = chosen and C.well or ((i % 2 == 1) and C.row1 or C.row2)
        row:SetBackdropColor(bg.r, bg.g, bg.b, chosen and 1 or (bg.a or 0.6))
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class] or nil
        local values = {}
        values.rank = pass and "-" or tostring(i)
        values.name = r.name or "?"
        if mode == "rolls" then
            local resp, place = LR:Response(r.rollType, rule)
            values.answer = pass and L["Passed"] or (resp and LR:ResponseLabel(resp)) or tostring(r.rollType or "")
            values.why = pass and "" or self:WhyHere(r, rule)
            if r.rollType == "PASS" then
                values.roll = "-"
            elseif r.bid then
                values.roll = (sealed and not ended) and L["sealed"] or string.format(L["bid %d"], r.bid)
            else
                values.roll = self:RollText(r, rule)
            end
            row.answerPlace = place
        else
            values.answer = r.listType == "prio" and L["PRIO"] or L["WISH"]
            values.why = (r.listType == "prio" and string.format(L["priority #%d"], r.order or 0)
                or string.format(L["wishlist #%d"], r.order or 0)) .. (r.inRaid and "" or (" \194\183 " .. L["absent"]))
            values.roll = "-"
        end
        local counter = counters[1]
        values.plus = counter and tostring(r.accts and r.accts[counter.key] or 0) or ""
        local ctx = mode == "lists" and self:GetPlayerContext(r.name) or nil
        local att = (ctx and ctx.att25) or r.att25 or 0
        values.att = att .. "%"
        for _, col in ipairs(TABLE_COLS) do
            local fs, at = row.cells[col.key], layout.byKey[col.key]
            fs:SetText(values[col.key] or "")
            if at and at.shown then
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", row, "LEFT", at.x + 4, 0)
                fs:SetWidth(math.max(1, at.w - 6))
                fs:Show()
            else
                fs:Hide()
            end
        end
        local nameInk = cc or C.text
        if pass or (mode == "lists" and not r.inRaid) then nameInk = C.labelDim end
        row.cells.name:SetTextColor(nameInk.r, nameInk.g, nameInk.b)
        local ansInk = (pass and C.labelDim) or (row.answerPlace == 1 and C.ok) or (row.answerPlace == 2 and C.gold) or C.text
        row.cells.answer:SetTextColor(ansInk.r, ansInk.g, ansInk.b)
        local attInk = (att >= 60 and C.ok) or (att >= 40 and C.gold) or C.danger
        row.cells.att:SetTextColor(attInk.r, attInk.g, attInk.b)
        row.cells.why:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
        row.tip = mode == "rolls" and self:RowTip(r, rule) or nil
        row:Show()
    end
    for i = #rows + 1, #f.rows do f.rows[i]:Hide() end
    f.scrollContent:SetHeight(math.max(1, #rows * (TABLE_ROW_H + 2)))

    -- ── The decision, and the buttons that carry it out ─────────────
    local decision
    if mode == "rolls" then
        decision = self:DecisionText(rows, rule, ended)
        if f.picked and first and f.picked ~= first.name then
            decision = decision .. " " .. string.format(L["You picked %s instead."], f.chosen)
        end
    elseif first then
        decision = string.format(L["%s is first on the lists: award it now, or open a roll."], first.name)
    elseif (tied or 0) > 1 then
        decision = string.format(L["%d share the first place on the lists: open a roll."], tied)
    else
        decision = L["Nobody has it on a list: open a roll."]
    end
    f.decision:SetText(item and decision or "")
    local isML = self:IsMasterLooter()
    local awardTo = f.chosen
    f.awardBtn.label:SetText(awardTo and string.format(L["Award to %s"], awardTo) or L["Award"])
    if item and awardTo and isML and (mode == "lists" or ended) then f.awardBtn:Enable() else f.awardBtn:Disable() end
    local rolling = ours and not ended
    if ours then f.openBtn:Hide(); f.endBtn:Show() else f.endBtn:Hide(); f.openBtn:Show() end
    if rolling then f.endBtn:Enable() else f.endBtn:Disable() end
    if item and not ours and isML then f.openBtn:Enable() else f.openBtn:Disable() end
    if item and isML then f.deBtn:Enable() else f.deBtn:Disable() end
    if ours then f.cancelBtn:Enable() else f.cancelBtn:Disable() end
    if self:LastAward() then f.undoBtn:Enable() else f.undoBtn:Disable() end
    self:UpdateRollTimer()
end

----------------------------------------------------------------------
-- What a row of the roll frame says of a candidate, in words (issue #337). Text only: every figure
-- is the loot rule's.
----------------------------------------------------------------------
-- The roll, and beside it what a bonus account added and what the two come to.
function LootMaster:RollText(r, rule)
    if not r.roll then return "-" end
    local bonus = GuildOS.LootRule:BonusOf(r, rule)
    if bonus > 0 then return string.format("%d |cffFF9900+%d|r = %d", r.roll, bonus, r.roll + bonus) end
    return tostring(r.roll)
end

-- The accounts the rule keeps, as the candidate stands on each: a counter as "+1", a bonus account by
-- its name, a queue as the place in it; and the rule's summed score, when it orders by one.
function LootMaster:AccountsText(r, rule)
    local LR = GuildOS.LootRule
    local text = ""
    for _, a in ipairs(LR:OwnAccounts(rule)) do
        local has = r.accts and r.accts[a.key]
        if a.type == "queue" then
            text = text .. (has and string.format("|cffFF9900#%d|r ", has) or "|cff888888#-|r ")
        elseif a.type == "bonus" then
            text = text .. string.format("|cffFF9900%s %d|r ", a.name or a.key, has or 0)
        else
            text = text .. string.format("|cffFF9900+%d|r ", has or 0)
        end
    end
    local score = LR:ScoreOf(r, rule)
    if score then text = text .. string.format(L["|cff4CB8FFscore %s|r "], string.format("%.1f", score)) end
    return text
end

-- The lines of a row's tooltip: the note the answer came with, then each part of its score.
function LootMaster:RowTip(r, rule)
    local LR = GuildOS.LootRule
    local lines = {}
    if r.note then lines[#lines + 1] = r.note end
    local score, parts = LR:ScoreOf(r, rule)
    if score then
        lines[#lines + 1] = string.format(L["Score: %s"], string.format("%.1f", score))
        for _, part in ipairs(parts) do
            lines[#lines + 1] = string.format("%s: %s x %s = %s", LR:PartLabel(part, rule),
                string.format("%.4g", part.value), string.format("%.4g", part.w), string.format("%.1f", part.points))
        end
    end
    return lines
end

----------------------------------------------------------------------
-- The loot table in words (issue #346). Text only: the order and every figure are the loot rule's.
----------------------------------------------------------------------
local function answerLabel(key, rule)
    local r = GuildOS.LootRule:Response(key, rule)
    return r and GuildOS.LootRule:ResponseLabel(r) or tostring(key or "")
end

-- The clause that says what put `a` ahead of `b` by `entry` of the rule's order.
local function decidingClause(entry, a, b, rule)
    local LR = GuildOS.LootRule
    if not entry then return string.format(L["everything ties with %s, and the name settles it"], b.name) end
    local k = entry.k
    if k == "response" then
        return string.format(L["answered %s, before %s's %s"], answerLabel(a.rollType, rule), b.name, answerLabel(b.rollType, rule))
    elseif k == "softres" then
        return string.format(L["reserved the item, and %s did not"], b.name)
    elseif k == "hardres" then
        return string.format(L["hard reserved the item, and %s did not"], b.name)
    elseif k == "prio" or k == "wishlist" then
        local va = k == "prio" and a.prioOrder or (a.wishlist and a.wishlist.order)
        local vb = k == "prio" and b.prioOrder or (b.wishlist and b.wishlist.order)
        local what = k == "prio" and L["officer priority"] or L["wishlist place"]
        if vb then return string.format(L["%s #%d, before %s's #%d"], what, va or 0, b.name, vb) end
        return string.format(L["%s #%d, and %s has none"], what, va or 0, b.name)
    elseif k == "received" then
        return string.format(L["received %d items, fewer than %s's %d"], a.recvCount or 0, b.name, b.recvCount or 0)
    elseif k == "attendance" then
        return string.format(L["attendance %d%%, over %s's %d%%"], a.att25 or 0, b.name, b.att25 or 0)
    elseif k == "points" then
        return string.format(L["%d points, over %s's %d"], a.dkp or 0, b.name, b.dkp or 0)
    elseif k == "bid" then
        return string.format(L["bid %d, over %s's %d"], a.bid or 0, b.name, b.bid or 0)
    elseif k == "roll" then
        local ra = (a.roll or 0) + LR:BonusOf(a, rule)
        local rb = (b.roll or 0) + LR:BonusOf(b, rule)
        return string.format(L["their roll %d beats %s's %d"], ra, b.name, rb)
    elseif k == "account" then
        local acct = LR:Counter(entry.acct, rule) or LR:Queue(entry.acct, rule)
        local name = (acct and acct.name) or tostring(entry.acct):upper()
        return string.format(L["%s %d, before %s's %d"], name, LR:Held(a, entry.acct, rule), b.name, LR:Held(b, entry.acct, rule))
    end
    local va, vb = LR:Compared(a, rule)[k], LR:Compared(b, rule)[k]
    return string.format(L["%s %s, over %s's %s"], LR:Label(k), tostring(va or 0), b.name, tostring(vb or 0))
end

-- Who comes first among `sorted` (the candidates in the rule's order) and why, in one sentence: what
-- the first two share that a raider reads as a reason (both reserved the item), then what parted
-- them. `ended`: the answers are closed, and the first one wins; before that they lead.
function LootMaster:DecisionText(sorted, rule, ended)
    rule = rule or self:Rule()
    local asked = {}
    for _, c in ipairs(sorted or {}) do
        if c.rollType ~= "PASS" then asked[#asked + 1] = c end
    end
    local first, second = asked[1], asked[2]
    if not first then return L["Nobody has asked for it yet."] end
    local lead = string.format(ended and L["%s wins"] or L["%s leads"], first.name)
    if not second then return string.format(L["%s: the only one who asked."], lead) end
    local entry = GuildOS.LootRule:DecidingEntry(first, second, rule)
    local clauses = {}
    for _, e in ipairs(rule.order or {}) do
        if e == entry then break end
        if (e.k == "softres" or e.k == "hardres") and first.softRes then
            clauses[#clauses + 1] = string.format(L["both reserved the item (%s too)"], second.name)
        end
    end
    clauses[#clauses + 1] = decidingClause(entry, first, second, rule)
    local text = lead .. ": " .. table.concat(clauses, L[", and "]) .. "."
    if GuildOS.LootRule:Council(rule) then text = text .. " " .. L["The council's vote decides."] end
    return text
end

-- Why a candidate is where the rule puts them, in a few words: a filter that read their answer as
-- another, then each figure the rule's order compares beside the answer and the roll, which have
-- columns of their own.
function LootMaster:WhyHere(c, rule)
    rule = rule or self:Rule()
    local LR = GuildOS.LootRule
    local parts = {}
    if c.asked and c.asked ~= c.rollType then
        local _, f = LR:AnswerFor(c, c.asked, rule)
        parts[#parts + 1] = f and self:FilterReason(f, c, rule)
            or string.format(L["%s read as %s"], answerLabel(c.asked, rule), answerLabel(c.rollType, rule))
    end
    for _, entry in ipairs(rule.order or {}) do
        local k = entry.k
        if k == "softres" or k == "hardres" then
            if c.softRes then parts[#parts + 1] = (c.softRes.hard and L["hard reserved"]) or L["reserved"] end
        elseif k == "prio" and c.prioOrder then
            parts[#parts + 1] = string.format(L["priority #%d"], c.prioOrder)
        elseif k == "wishlist" and c.wishlist then
            parts[#parts + 1] = string.format(L["wishlist #%d"], c.wishlist.order or 0)
        elseif k == "received" and (c.recvCount or 0) > 0 then
            parts[#parts + 1] = string.format(L["already won %d"], c.recvCount)
        elseif k == "points" then
            parts[#parts + 1] = string.format(L["%d points"], c.dkp or 0)
        elseif k == "pr" then
            parts[#parts + 1] = string.format("PR %.2f", c.pr or 0)
        elseif k == "account" then
            local acct = LR:Counter(entry.acct, rule) or LR:Queue(entry.acct, rule)
            local held = LR:Held(c, entry.acct, rule)
            if acct and acct.type == "queue" then
                parts[#parts + 1] = (c.accts and c.accts[entry.acct]) and string.format("%s #%d", acct.name or acct.key, held) or nil
            else
                parts[#parts + 1] = string.format("%s: %d", (acct and acct.name) or tostring(entry.acct):upper(), held)
            end
        elseif k == "score" then
            local score = LR:ScoreOf(c, rule)
            if score then parts[#parts + 1] = string.format(L["score %s"], string.format("%.1f", score)) end
        end
    end
    return table.concat(parts, " \194\183 ")
end

-- What was given out tonight from this client's award log (the core's, "" the guild's), newest first,
-- an award taken back left out: the night is the last NIGHT_SPAN seconds.
local NIGHT_SPAN = 12 * 3600
function LootMaster:NightAwards(core)
    local CM = GuildOS.CoreManager
    local log = (CM and CM.GetAwardHistory and CM:GetAwardHistory(core or self:ActiveCore()))
        or (GuildOS.db.lootMaster and GuildOS.db.lootMaster.awardHistory) or {}
    local since, out = GetServerTime() - NIGHT_SPAN, {}
    for _, a in ipairs(log) do
        if (a.timestamp or 0) >= since and not a.undone then out[#out + 1] = a end
    end
    return out
end

-- Where an item of the boss's loot stands, for the loot table's list (issue #346): "awarded" (and to
-- whom), "rolling" (with how many asked), "exception" (what the rule's exception does with it) or
-- "queued". `item` is { link, slot, quality } as the loot window lists it.
function LootMaster:ItemState(item)
    local loot = self.activeLoot
    if loot and loot.link == item.link and not loot.delivered then
        if loot.ended then return "ended", string.format(L["%d asked, closed"], self:CountRolls()) end
        return "rolling", string.format(L["%d asked, rolling"], self:CountRolls())
    end
    for _, a in ipairs(self:NightAwards()) do
        if a.link == item.link and (a.timestamp or 0) >= (self.lootShownAt or 0) then
            return "awarded", string.format(L["to %s"], a.player or "?")
        end
    end
    local LR = GuildOS.LootRule
    local facts = self:ItemFacts(item.link, item.slot)
    local x = facts and LR:ExceptionFor(LR:Active(), facts)
    if x then
        local to = (x.to == "bank" and L["bank"]) or (x.to == "de" and L["disenchant"]) or LR:ExceptionLabel(x)
        return "exception", string.format(L["exception: %s"], to)
    end
    return "queued", L["queued"]
end

----------------------------------------------------------------------
-- Update timer display
----------------------------------------------------------------------
function LootMaster:UpdateRollTimer()
    if not self.rollFrame then return end
    if not self.activeLoot then
        self.rollFrame.timerText:SetText("")
        return
    end

    if self.activeLoot.ended then
        -- With a council's vote on the item (issue #336), where the vote stands.
        local Council = GuildOS.LootCouncil
        local view = Council and self.activeLoot.council and Council:View()
        if view then
            self.rollFrame.timerText:SetText("|cffFFFF00" .. Council:StatusText(view) .. "|r")
            return
        end
        self.rollFrame.timerText:SetText(L["|cffFF4444Rolling ended - click Award|r"])
        return
    end

    if not self.activeLoot.endTime then
        self.rollFrame.timerText:SetText(L["|cff888888No timer|r"])
        return
    end

    local remaining = self.activeLoot.endTime - GetServerTime()
    if remaining > 0 then
        self.rollFrame.timerText:SetText(string.format(L["|cffFFFF00%ds remaining|r  |  %d rolls"], remaining, self:CountRolls()))
    else
        self.rollFrame.timerText:SetText(L["|cffFF4444Time's up!|r"])
    end
end

function LootMaster:CountRolls()
    local n = 0
    for _ in pairs(self.rolls) do n = n + 1 end
    return n
end

----------------------------------------------------------------------
-- Disenchanter: designated player who receives unwanted items to DE
----------------------------------------------------------------------
function LootMaster:GetDisenchanter()
    return self:GetCfg().disenchanter or self.disenchanter or ""
end

function LootMaster:SetDisenchanter(name)
    self.disenchanter = name or ""
    self:SaveCfgKey("disenchanter", self.disenchanter)
end

-- Rarity threshold (item quality id) the ML window reacts to.
LootMaster.THRESHOLD_NAMES = {
    [2] = L["Uncommon (green)"],
    [3] = L["Rare (blue)"],
    [4] = L["Epic (purple)"],
    [5] = L["Legendary (orange)"],
}

function LootMaster:GetLootThreshold()
    return self:GetCfg().lootThreshold or self.LOOT_THRESHOLD or 3
end

function LootMaster:SetLootThreshold(q)
    q = tonumber(q) or 3
    if q < 2 then q = 2 elseif q > 5 then q = 5 end
    self.LOOT_THRESHOLD = q
    self:SaveCfgKey("lootThreshold", q)
end

-- The bank character (issue #335): who receives an item an exception sends "to the bank". Kept with
-- the loot settings, beside the disenchanter.
function LootMaster:GetBank()
    return self:GetCfg().bank or ""
end

function LootMaster:SetBank(name)
    self:SaveCfgKey("bank", strtrim(tostring(name or "")))
end

-- What the client knows of an item when it is announced, for the rule's exceptions: its id, quality,
-- class and how it binds, the loot threshold of the loot settings, the raid it is in and, while the
-- item is in the open loot window of a boss killed a short while ago, that boss.
local BOSS_LOOT_WINDOW = 600   -- seconds after a kill its loot window still names the boss
function LootMaster:ItemFacts(itemLink, lootSlot)
    local id = tonumber(tostring(itemLink):match("item:(%d+)"))
    local _, _, quality, _, _, _, _, _, _, _, _, classID, subclassID, bindType = GuildOS.Compat.GetItemInfo(itemLink)
    local facts = {
        id = id, quality = quality, classID = classID, subclassID = subclassID, bindType = bindType,
        threshold = self:GetLootThreshold(),
    }
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType == "raid" then facts.raid = instanceID end
    local raid = GuildOS.RaidTracker and GuildOS.RaidTracker.currentRaid
    if self.lootWindowOpen and lootSlot and raid and type(raid.encounters) == "table" then
        local last = raid.encounters[#raid.encounters]
        if last and last.success and last.endTime and GetServerTime() - last.endTime <= BOSS_LOOT_WINDOW then
            facts.boss = last.id
        end
    end
    return facts
end

-- An exception's fixed destination (issue #335): the item goes to the bank character or to the
-- disenchanter with no roll, the raid is told which exception said so, and nobody is charged.
-- `reason` "norolls": nobody asked for it. With no character set for the destination the loot master
-- is told, and nothing is given.
function LootMaster:SendToDestination(exception, itemLink, lootSlot, itemId, reason)
    local toBank = exception.to == "bank"
    local name = toBank and self:GetBank() or self:GetDisenchanter()
    if not name or name == "" then
        GuildOS:Print("|cffFF4444" .. (toBank and L["No bank character set."] or L["No disenchanter set."]) .. "|r "
            .. L["Configure it in the Loot Master options."])
        if not reason then self.activeLoot = nil end
        return false
    end
    self:StopRollTimer()
    if not self.activeLoot then self:SetActiveLoot(itemLink or "", lootSlot, itemId or 0) end
    local label = GuildOS.LootRule:ExceptionLabel(exception)
    local msg
    if toBank then
        msg = string.format(L["[Loot] %s goes to the guild bank (%s) - exception: %s"], itemLink or L["item"], name, label)
    elseif reason == "norolls" then
        msg = string.format(L["[Loot] %s - nobody rolled. Sending to Disenchant: %s"], itemLink or L["item"], name)
    else
        msg = string.format(L["[Loot] %s goes to Disenchant (%s) - exception: %s"], itemLink or L["item"], name, label)
    end
    self:SafeSendChat(msg, "RAID")
    self.activeLoot.exception = exception   -- the award's record names it (issue #336)
    self:AwardLoot(name, true, true)   -- silent: the line above said it; free: nobody pays for it
    return true
end

-- Award the active item (or the provided item) to the disenchanter.
-- Called when ML clicks "Send to DE" from any loot UI.
function LootMaster:SendToDisenchanter(itemLink, lootSlot, itemId, reason)
    local deName = self:GetDisenchanter()
    if not deName or deName == "" then
        GuildOS:Print("|cffFF4444" .. L["No disenchanter set."] .. "|r " .. L["Configure it in the Loot Master options."])
        return
    end

    -- Ensure activeLoot is populated so AwardLoot can use it
    if not self.activeLoot then
        self:SetActiveLoot(itemLink or "", lootSlot, itemId or 0)
    end

    local msg
    if reason == "norolls" then
        msg = string.format(L["[Loot] %s - nobody rolled. Sending to Disenchant: %s"],
            itemLink or L["item"], deName)
    else
        msg = string.format(L["[Loot] %s delivered to Disenchant (%s)"],
            itemLink or L["item"], deName)
    end
    self:SafeSendChat(msg, "RAID")

    -- silent: the line above said it; free: an item nobody keeps costs nobody anything. The button
    -- pressed after a roll with a price to enter used to charge every asker "Lost the roll", and the
    -- disenchanter the item's price.
    self:AwardLoot(deName, true, true)
end

----------------------------------------------------------------------
-- Roll from Bag — start a full GuildOS roll for an item already in
-- the ML's bags (e.g. items picked up to distribute later).
-- Awards always go through the trade path (QueueForTrade) because
-- there is no ML loot window for bag items.
----------------------------------------------------------------------
function LootMaster:RollFromBag(bag, slot)
    if not IsInRaid() and not self.testMode then
        GuildOS:Print("|cffFF4444[LootMaster]|r " .. L["Only available in a raid."])
        return
    end
    if not self:IsMasterLooter() then
        GuildOS:Print("|cffFF4444[LootMaster]|r " .. L["Only the Master Looter can use this function."])
        return
    end

    -- Block if a roll session is already in progress
    if self.activeLoot and not self.activeLoot.delivered then
        GuildOS:Print("|cffFF9900[LootMaster]|r " .. L["Roll in progress: "] .. (self.activeLoot.link or "?"))
        return
    end

    -- Get item link from bag slot
    local itemLink = GuildOS.Compat.GetContainerItemLink(bag, slot)

    if not itemLink then return end

    -- Respect the configured rarity threshold; skip if info not cached yet
    local _, _, quality = GuildOS.Compat.GetItemInfo(itemLink)
    if quality and quality < (self.LOOT_THRESHOLD or 3) then
        GuildOS:Print("|cffFF9900[LootMaster]|r " .. L["Item below the configured rarity threshold."])
        return
    end

    -- Force trade-delivery path (no loot window is open for bag items)
    self.lootWindowOpen = false

    GuildOS:Print("|cff00ff00[LootMaster]|r " .. L["Starting bag roll: "] .. itemLink)
    self:AnnounceItem(itemLink, nil)
end
