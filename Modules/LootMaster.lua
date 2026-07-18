----------------------------------------------------------------------
-- BRutus Guild Manager - Loot Master (Gargul-style)
-- Master Looter announces items, players roll MS/OS, ML awards loot.
-- Integrates with wishlists to show interest on items.
----------------------------------------------------------------------
local LootMaster = {}
BRutus.LootMaster = LootMaster
local L = BRutus.L

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
LootMaster.rollPattern       = nil    -- built in Initialize() from RANDOM_ROLL_RESULT
LootMaster.disenchanter      = ""     -- runtime cache; persisted to BRutus.db.lootMaster.disenchanter

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
        BRutus:Print("|cff888888[" .. (channel or "CHAT") .. "]|r " .. msg)
    end
end

function LootMaster:SafeSendAddon(prefix, payload, channel)
    if IsInRaid() and not self.testMode then
        C_ChatInfo.SendAddonMessage(prefix, payload, channel)
    end
end

----------------------------------------------------------------------
-- Per-core config helpers.
-- All reads go through GetCfg() so they automatically reflect the
-- active core's overrides; all writes go through SaveCfgKey() so they
-- are persisted in the right place.
----------------------------------------------------------------------
function LootMaster:GetCfg()
    if BRutus.CoreManager then
        return BRutus.CoreManager:GetLootConfig()
    end
    return BRutus.db.lootMaster or {}
end

function LootMaster:SaveCfgKey(key, value)
    if BRutus.CoreManager then
        BRutus.CoreManager:SetLootConfigKey(key, value)
    elseif BRutus.db.lootMaster then
        BRutus.db.lootMaster[key] = value
    end
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
    if BRutus.LootSystemActive and not BRutus:LootSystemActive() then
        return false
    end
    local m = BRutus.db and BRutus.db.settings and BRutus.db.settings.modules
    return not m or m.lootMaster ~= false
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function LootMaster:Initialize()
    if not BRutus.db.lootMaster then
        BRutus.db.lootMaster = {
            rollDuration = 30,
            autoAnnounce = true,
            wishlistOnlyMode = false,
            awardHistory = {},
        }
    end

    -- Ensure loot-distribution settings exist in the global fallback (added in v2)
    local lmdb = BRutus.db.lootMaster
    if lmdb.minAttendancePct == nil then lmdb.minAttendancePct = 0    end
    if lmdb.attTiebreaker    == nil then lmdb.attTiebreaker    = true end
    if lmdb.recvPenalty      == nil then lmdb.recvPenalty      = true end
    if lmdb.awardHistory     == nil then lmdb.awardHistory     = {}   end
    if lmdb.disenchanter     == nil then lmdb.disenchanter     = ""   end
    if lmdb.lootThreshold    == nil then lmdb.lootThreshold    = 3    end

    -- Cache active values (read via GetCfg so cores are respected from the start)
    local cfg = self:GetCfg()
    self.ROLL_DURATION      = cfg.rollDuration or 30
    self.AUTO_ANNOUNCE      = cfg.autoAnnounce
    self.WISHLIST_ONLY_MODE = cfg.wishlistOnlyMode or false
    self.disenchanter       = cfg.disenchanter or ""
    self.LOOT_THRESHOLD     = cfg.lootThreshold or 3
    self.pendingTrades      = {}

    -- Build /roll detection pattern from localized RANDOM_ROLL_RESULT global
    -- e.g. EN: "%s rolls %d (%d-%d)."  → ^(.+) rolls (%d+) %((%d+)%-(%d+)%)%.$
    do
        local tmpl = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)."
        local p = tmpl:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
        p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
        self.rollPattern = "^" .. p .. "$"
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LOOT_OPENED")
    frame:RegisterEvent("LOOT_CLOSED")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("CHAT_MSG_SYSTEM")  -- capture /roll results
    frame:RegisterEvent("TRADE_SHOW")
    frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
    -- GROUP_LEFT: disenchanter is now persisted to DB, no need to clear
    -- START_LOOT_ROLL intentionally NOT registered: it only fires under native
    -- Group Loot (need/greed/pass), where there is no BRutus master looter
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

    C_ChatInfo.RegisterAddonMessagePrefix("BRutusLM")
    self.eventFrame = frame

    -- Alt+Click on any bag item starts a BRutus roll for that item (ML only).
    -- Uses the trade-delivery path since there is no ML loot window for bag items.
    -- Guard: only hook if the default UI function exists (TBC Anniversary).
    if ContainerFrameItemButton_OnModifiedClick then
        hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(btn, _button)
            if not LootMaster:IsModuleEnabled() then return end
            if not IsAltKeyDown() then return end
            if not LootMaster:IsMasterLooter() then return end
            local bagId  = btn:GetParent():GetID()
            local slotId = btn:GetID()
            LootMaster:RollFromBag(bagId, slotId)
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

    -- 25-man attendance %
    if BRutus.RaidTracker then
        local pKey = BRutus:GetPlayerKey(playerName, GetRealmName())
        ctx.att25 = BRutus.RaidTracker:GetAttendance25ManPercent(pKey) or 0
    end

    -- Items received this lockout: count ML-awarded loot history entries
    -- from the current raid session start (or last 8 hours as fallback).
    if BRutus.db and BRutus.db.lootHistory then
        local sessionStart = 0
        if BRutus.RaidTracker and BRutus.RaidTracker.currentRaid then
            sessionStart = BRutus.RaidTracker.currentRaid.startTime or 0
        end
        if sessionStart == 0 then
            sessionStart = GetServerTime() - (8 * 3600)
        end
        local realm  = GetRealmName() or ""
        local pKey   = playerName .. "-" .. realm
        for _, entry in ipairs(BRutus.db.lootHistory) do
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
                local myName = UnitName("player")
                local name = GetRaidRosterInfo(masterLooterRaidID)
                if name and name == myName then return true end
            end
        end
    end

    -- 3. C_PartyInfo shim (Anniversary / Retail fallback)
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local method, masterLooterRaidID = C_PartyInfo.GetLootMethod()
        -- method 2 = master loot in the C_PartyInfo enum
        if method == 2 and masterLooterRaidID then
            local myName = UnitName("player")
            local name = GetRaidRosterInfo(masterLooterRaidID)
            if name and name == myName then return true end
        end
    end

    return false
end

----------------------------------------------------------------------
-- /roll capture: start/stop listening for CHAT_MSG_SYSTEM roll results
----------------------------------------------------------------------
function LootMaster:StartListeningForRolls()
    self.listeningForRolls = true
end

function LootMaster:StopListeningForRolls()
    self.listeningForRolls = false
end

-- Called on every CHAT_MSG_SYSTEM event
function LootMaster:OnSystemMessage(message)
    if not self.listeningForRolls or not self.activeLoot then return end
    self:ProcessSystemRoll(message)
end

----------------------------------------------------------------------
-- Parse a CHAT_MSG_SYSTEM /roll line and register it as MS or OS.
--   MS = RandomRoll(1, 100)  |  OS = RandomRoll(1, 99)
-- All other roll ranges are ignored.
----------------------------------------------------------------------
function LootMaster:ProcessSystemRoll(message)
    if not self.rollPattern then return end

    local roller, roll, low, high = string.match(message, self.rollPattern)
    if not roller then return end

    roll = tonumber(roll)
    low  = tonumber(low)
    high = tonumber(high)
    if not roll or not low or not high then return end

    -- Only the two agreed-upon ranges count; ignore all other /roll usage
    local rollType
    if low == 1 and high == 100 then
        rollType = "MS"
    elseif low == 1 and high == 99 then
        rollType = "OS"
    else
        return
    end

    -- Strip realm suffix that may appear in some client versions
    local cleanName = roller:match("^([^%-]+)") or roller

    -- Verify the roller is currently in the raid (or testMode)
    local inRaid = self.testMode
    if not inRaid then
        local numMembers = GetNumGroupMembers() or 0
        for i = 1, numMembers do
            local uName = UnitName("raid" .. i)
            if uName and (uName == cleanName or uName == roller) then
                inRaid = true
                break
            end
        end
        -- Also accept own roll (solo / testMode outside raid)
        if not inRaid and cleanName == UnitName("player") then
            inRaid = true
        end
    end

    if not inRaid then return end

    -- Restricted-roll session: only allowed players may roll; ignore everyone else silently
    if self.restrictedRollers and not self.restrictedRollers[strlower(cleanName)] then
        return
    end

    self:RegisterRoll(cleanName, rollType, roll)
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
                local bindType = select(14, GetItemInfo(itemId))
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
        BRutus.LootMaster:ShowLootFrame(items)
    end
end

function LootMaster:OnLootClosed()
    self.isMLSession = false
    self.lootWindowOpen = false

    -- If there is a pending loot session (roll in progress or ended but not yet
    -- awarded), warn the ML and keep activeLoot intact so Award/DE still work
    -- via the trade path (lootWindowOpen=false → QueueForTrade).
    if self.activeLoot and not self.activeLoot.delivered then
        BRutus:Print("|cffFF9900[LootMaster]|r " .. L["Loot window closed before delivery - use the roll frame to deliver the item via trade."])
    end
end

----------------------------------------------------------------------
-- Check if current player has itemId on their native wishlist.
-- Reads from the per-char wishlists table (BRutus.db.wishlists[charKey]),
-- NOT from the legacy flat myWishlist key which is nil'd out on migration.
----------------------------------------------------------------------
function LootMaster:PlayerHasItemOnWishlist(itemId)
    if not BRutus.Wishlist then return false end
    local list = BRutus.Wishlist:GetMyList()
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
    if not BRutus.Wishlist or not itemId or itemId == 0 then return nil end

    local interest = BRutus.Wishlist:GetItemInterest(itemId)
    if not interest or #interest == 0 then return nil end

    -- Build set of players currently in raid
    local inRaid = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local name = UnitName("raid" .. i)
        if name then
            inRaid[strlower(name)] = select(2, UnitClass("raid" .. i)) or "UNKNOWN"
        end
    end
    -- In testMode, treat the current player as in raid so council logic is testable
    if self.testMode then
        local myName = UnitName("player")
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
    if not BRutus.db or not BRutus.db.lootPrios then return nil end
    local prioList = BRutus.db.lootPrios[itemId]
    if not prioList or #prioList == 0 then return nil end

    -- Build set of players currently in raid
    local inRaid = {}
    local numMembers = GetNumGroupMembers()
    for i = 1, numMembers do
        local name = UnitName("raid" .. i)
        if name then inRaid[strlower(name)] = true end
    end
    if self.testMode then
        local myName = UnitName("player")
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
-- Announce an item for rolling.
-- Priority logic (always active, regardless of WISHLIST_ONLY_MODE):
--   ≥ 2 players tied at top wishlist position in raid → restricted roll (only they roll)
--   1 clear winner + WISHLIST_ONLY_MODE          → AutoCouncilAward (direct award prompt)
--   otherwise                                 → open MS/OS roll for all
----------------------------------------------------------------------
function LootMaster:AnnounceItem(itemLink, lootSlot)
    if not IsInRaid() and not self.testMode then
        BRutus:Print(L["You must be in a raid to announce loot."])
        return
    end

    -- Clear previous session
    self.rolls             = {}
    self.restrictedRollers = nil
    self.activeLoot = {
        link      = itemLink,
        slot      = lootSlot,
        startTime = GetServerTime(),
        endTime   = GetServerTime() + self.ROLL_DURATION,
    }

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    self.activeLoot.itemId = itemId

    -- The guild's chosen loot system (Settings) decides the default flow:
    -- "wishlist"/"tmb" force wishlist auto-council; "dkp"/"rolls" open a roll
    -- (DKP just changes how the roll frame ranks and what award charges).
    local lootSystem = (BRutus.GetLootSystem and BRutus:GetLootSystem()) or "rolls"
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
    -- Main announce (DKP mode rolls register interest; the ML awards by standings)
    local lootSystem = (BRutus.GetLootSystem and BRutus:GetLootSystem()) or "rolls"
    local msg
    if lootSystem == "dkp" then
        msg = format(L["[DKP] %s  -  /roll to bid, highest DKP wins  -  %ds"],
            itemLink, self.ROLL_DURATION)
    else
        msg = format(L["[ROLL] %s  -  /roll 1-100 = MS  -  /roll 1-99 = OS  -  %ds"],
            itemLink, self.ROLL_DURATION)
    end
    self:SafeSendChat(msg, "RAID_WARNING")

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

    -- Send addon message so BRutus users get the roll popup
    local payload = format("ANNOUNCE|%s|%d|%d|0", itemLink, self.ROLL_DURATION, itemId or 0)
    self:SafeSendAddon("BRutusLM", payload, "RAID")

    -- Start capturing /roll results from CHAT_MSG_SYSTEM
    self:StartListeningForRolls()

    -- Start countdown timer
    if self.rollTimer then self.rollTimer:Cancel() end
    self.rollTimer = C_Timer.NewTimer(self.ROLL_DURATION, function()
        LootMaster:EndRolling()
    end)
    self:ScheduleCountdownWarnings()

    -- Update UI — always open/refresh the ML roll frame
    self:ShowRollFrame()

    BRutus:Print(L["Loot announced: "] .. itemLink .. " (" .. self.ROLL_DURATION .. "s)")
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
    if not BRutus.SoftRes or not itemId or itemId == 0 then return end
    local srList = BRutus.SoftRes:GetInRaidReserves(itemId)
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
    self:SafeSendChat(
        string.format(L["[ROLL] %s  -  Tie [%s]: %s  -  /roll 1-100 MS  -  /roll 1-99 OS  -  %ds"],
            itemLink, orderStr, nameStr, self.ROLL_DURATION),
        "RAID_WARNING"
    )
    self:AnnounceSoftReserves(itemId or (self.activeLoot and self.activeLoot.itemId))

    -- Addon comm: show popup to BRutus users who have the item on their wishlist
    itemId = itemId or (self.activeLoot and self.activeLoot.itemId) or 0
    local payload = string.format("ANNOUNCE|%s|%d|%d|1", itemLink, self.ROLL_DURATION, itemId)
    self:SafeSendAddon("BRutusLM", payload, "RAID")

    -- Start capturing /roll (restricted list enforced in ProcessSystemRoll)
    self:StartListeningForRolls()

    -- Timer
    if self.rollTimer then self.rollTimer:Cancel() end
    self.rollTimer = C_Timer.NewTimer(self.ROLL_DURATION, function()
        LootMaster:EndRolling()
    end)
    self:ScheduleCountdownWarnings()

    -- Show roll tracker for ML
    self:ShowRollFrame()

    BRutus:Print(string.format(L["|cffFFD700Wishlist tie|r [wishlist #%d]: %s - only they may roll (%ds)"],
        tied[1].order, nameStr, self.ROLL_DURATION))
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
    local C = BRutus.Colors
    local UI = BRutus.UI

    if self.councilFrame then self.councilFrame:Hide() end

    local numRows = allCandidates and #allCandidates or 0
    local f = CreateFrame("Frame", "BRutusCouncilFrame", UIParent, "BackdropTemplate")
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
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText(L["Wishlist Council"])

    -- Item
    local itemText = f:CreateFontString(nil, "OVERLAY")
    itemText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    itemText:SetPoint("TOP", 0, -26)
    itemText:SetText(itemLink or L["Unknown Item"])

    -- Winner line
    local CLASS_COLORS = RAID_CLASS_COLORS
    local cc = CLASS_COLORS[winner.class] or { r = 0.8, g = 0.8, b = 0.8 }
    local winText = f:CreateFontString(nil, "OVERLAY")
    winText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
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
            row:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
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
    deCouncilBtn:SetPoint("BOTTOM", 0, 10)
    deCouncilBtn:SetBackdropColor(0.260, 0.160, 0.360, 0.7)
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
    if prefix ~= "BRutusLM" then return end
    if channel ~= "RAID" and channel ~= "RAID_LEADER" then return end

    local cmd, rest = msg:match("^(%w+)|(.+)$")
    if not cmd then return end

    if cmd == "ANNOUNCE" then
        -- Another ML announced an item - show roll popup if we're not ML
        if not self:IsMasterLooter() then
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

            self:ShowRollPopup(link, duration, itemId)
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
            BRutus:Print(string.format(L["|cffFFD700Loot:|r %s awarded to |cff00ff00%s|r"], link, awardedTo))

            -- Record to loot history only if the sender is an officer and not ourselves
            -- (the awarder already recorded locally in AwardLoot).
            local senderName = sender and sender:match("^([^-]+)") or ""
            if senderName ~= UnitName("player")
                and BRutus:IsOfficerByName(senderName)
                and BRutus.LootTracker
            then
                local realm = GetRealmName() or "Unknown"
                local itemName = GetItemInfo(link)
                local quality  = tonumber(awardQuality) or 4
                BRutus.LootTracker:RecordMLAward({
                    itemLink   = link,
                    itemName   = itemName or "",
                    quality    = quality,
                    player     = awardedTo,
                    playerKey  = awardedTo .. "-" .. realm,
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
-- Register a player's /roll result (called from ProcessSystemRoll).
-- name: bare player name (no realm);  rollType: "MS" or "OS";
-- roll: the actual number the player rolled.
----------------------------------------------------------------------
function LootMaster:RegisterRoll(name, rollType, roll)
    if not self.activeLoot then return end

    local key = name .. "-" .. (GetRealmName() or "")

    -- Attendance gate: auto-downgrade MS → OS if below minimum threshold
    local ctx = self:GetPlayerContext(name)
    local minAtt = self:GetCfg().minAttendancePct or 0
    if rollType == "MS" and minAtt > 0 and ctx.att25 < minAtt then
        rollType = "OS"
        self:SafeSendChat(string.format(
            L["[Loot] %s: MS converted to OS (attendance %d%% below minimum %d%%)"],
            name, ctx.att25, minAtt), "RAID")
    end

    -- Wishlist lookup
    local wishInfo = nil
    if BRutus.Wishlist and self.activeLoot.itemId then
        local interest = BRutus.Wishlist:GetItemInterest(self.activeLoot.itemId)
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
    if BRutus.db and BRutus.db.lootPrios and self.activeLoot.itemId then
        local prioList = BRutus.db.lootPrios[self.activeLoot.itemId]
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
    if BRutus.SoftRes and self.activeLoot.itemId then
        for _, entry in ipairs(BRutus.SoftRes:GetReserves(self.activeLoot.itemId)) do
            if strlower(entry.name or "") == strlower(name) then
                srInfo = { hard = entry.hard or false }
                break
            end
        end
    end

    -- Class from raid unit or stored member data
    local class = "UNKNOWN"
    local numMembers = GetNumGroupMembers() or 0
    if numMembers > 0 then
        for i = 1, numMembers do
            local unit = "raid" .. i
            local uName = UnitName(unit)
            if uName and uName == name then
                class = select(2, UnitClass(unit)) or "UNKNOWN"
                break
            end
        end
    end
    if class == "UNKNOWN" then
        local pKey = BRutus:GetPlayerKey(name, GetRealmName())
        local memberData = BRutus.db.members and BRutus.db.members[pKey]
        if memberData and memberData.class then
            class = memberData.class
        elseif name == UnitName("player") then
            class = select(2, UnitClass("player")) or "UNKNOWN"
        end
    end

    self.rolls[key] = {
        name       = name,
        class      = class,
        rollType   = rollType,
        roll       = roll,
        wishlist   = wishInfo,
        prioOrder  = prioOrder,
        softRes    = srInfo,
        att25      = ctx.att25,
        recvCount  = ctx.recvThisLockout,
        dkp        = (BRutus.Points and BRutus.Points:Get(BRutus:GetPlayerKey(name, GetRealmName()))) or 0,
    }

    -- Announce prio or wishlist position to raid
    if prioOrder then
        self:SafeSendChat(string.format(L["[Loot] %s: %s (Official Prio #%d)"],
            name, rollType, prioOrder), "RAID")
    elseif wishInfo then
        self:SafeSendChat(string.format(L["[Loot] %s: %s (Wishlist #%d)"],
            name, rollType, wishInfo.order), "RAID")
    end

    -- Refresh ML roll frame
    if self.rollFrame and self.rollFrame:IsShown() then
        self:RefreshRollFrame()
    end
end

----------------------------------------------------------------------
-- End rolling and display results
----------------------------------------------------------------------
function LootMaster:EndRolling()
    if not self.activeLoot then return end

    self:StopListeningForRolls()
    self.restrictedRollers = nil

    if self.rollTimer then
        self.rollTimer:Cancel()
        self.rollTimer = nil
    end

    -- Sort rolls: MS first (by wishlist order then roll), then OS (by roll)
    local sorted = {}
    for _, r in pairs(self.rolls) do
        if r.rollType ~= "PASS" then
            table.insert(sorted, r)
        end
    end

    table.sort(sorted, function(a, b)
        -- MS beats OS
        if a.rollType ~= b.rollType then
            return a.rollType == "MS"
        end
        -- Officer prio: lower index wins (no prio = 999)
        local aPrio = a.prioOrder or 999
        local bPrio = b.prioOrder or 999
        if aPrio ~= bPrio then return aPrio < bPrio end
        -- Soft reserve: SR holder beats non-SR (below officer prio, above wishlist)
        local aSR = a.softRes and 1 or 2
        local bSR = b.softRes and 1 or 2
        if aSR ~= bSR then return aSR < bSR end
        -- Wishlist priority: lower order number wins; no wishlist entry ranks last
        local aOrder = a.wishlist and a.wishlist.order or 999
        local bOrder = b.wishlist and b.wishlist.order or 999
        if aOrder ~= bOrder then return aOrder < bOrder end
        -- Received tiebreaker: fewer items received this lockout wins (when enabled)
        local _cfg = LootMaster:GetCfg()
        if _cfg.recvPenalty ~= false then
            local aRecv = a.recvCount or 0
            local bRecv = b.recvCount or 0
            if aRecv ~= bRecv then return aRecv < bRecv end
        end
        -- Attendance tiebreaker: higher 25-man attendance wins
        if _cfg.attTiebreaker and (a.att25 or 0) ~= (b.att25 or 0) then
            return (a.att25 or 0) > (b.att25 or 0)
        end
        -- Final tiebreaker: higher roll
        return a.roll > b.roll
    end)

    self.activeLoot.sortedResults = sorted
    self.activeLoot.ended = true

    -- Announce winner in raid
    if #sorted > 0 then
        local winner = sorted[1]
        local wishStr = ""
        if winner.prioOrder then
            wishStr = string.format(L[" [Official Prio #%d]"], winner.prioOrder)
        elseif winner.softRes then
            wishStr = winner.softRes.hard and L[" [Hard Reserve]"] or L[" [Soft Reserve]"]
        elseif winner.wishlist then
            wishStr = string.format(L[" [Wishlist #%d]"], winner.wishlist.order)
        end
        self:SafeSendChat(string.format(L["[WINNER] %s - %s (%d)%s - %s"],
            winner.name, winner.rollType, winner.roll, wishStr, self.activeLoot.link), "RAID_WARNING")
    else
        self:SafeSendChat(L["[Roll] No roll received for "] .. self.activeLoot.link, "RAID_WARNING")
    end

    -- Refresh UI
    if self.rollFrame and self.rollFrame:IsShown() then
        self:RefreshRollFrame()
    end
end

----------------------------------------------------------------------
-- Award loot to a player (Gargul-style two-path distribution)
----------------------------------------------------------------------
function LootMaster:AwardLoot(playerName, silent)
    if not self.activeLoot then return end
    if not self:IsMasterLooter() then
        BRutus:Print(L["You are not the Master Looter."])
        return
    end

    local itemLink = self.activeLoot.link
    -- Default to 0 so the "%d" in the AWARD payload (and history record) never sees nil
    -- for malformed/non-item links. The receiver skips this field with "%d+", so 0 is safe.
    local itemId = self.activeLoot.itemId or 0
    local slot = self.activeLoot.slot
    local awarded = false

    -- Path 1: ML loot window open + ML API available -> GiveMasterLoot
    if self.lootWindowOpen and slot and GiveMasterLoot and GetMasterLootCandidate then
        local numCandidates = 40
        for i = 1, numCandidates do
            local candidateName = GetMasterLootCandidate(slot, i)
            if candidateName then
                local cName = candidateName:match("^([^-]+)")
                if cName == playerName then
                    GiveMasterLoot(slot, i)
                    awarded = true
                    break
                end
            end
        end
    end

    -- Path 2: No ML API or loot window closed -> queue for trade
    if not awarded then
        local isMe = (playerName == UnitName("player"))
        if not isMe then
            self:QueueForTrade(playerName, itemLink, itemId)
        end
    end

    -- Gather extra context for history and broadcast
    local _, _, itemQuality = GetItemInfo(itemLink)
    itemQuality = itemQuality or 4
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    local raidName = ""
    if BRutus.RaidTracker and BRutus.RaidTracker.RAID_INSTANCES then
        raidName = BRutus.RaidTracker.RAID_INSTANCES[instanceID] or ""
    end
    local realm = GetRealmName() or "Unknown"

    -- Broadcast award (extended format: playerName|itemId|quality|raidName|itemLink)
    -- Peers with BRutus will record this to their loot history after verifying
    -- the sender is an officer.
    local payload = string.format("AWARD|%s|%d|%d|%s|%s", playerName, itemId, itemQuality, raidName, itemLink)
    self:SafeSendAddon("BRutusLM", payload, "RAID")

    -- Announce (skipped when silent=true, e.g. SendToDisenchanter already announced)
    if not silent then
        self:SafeSendChat(string.format(L["[Loot] %s delivered to %s"], itemLink, playerName), "RAID")
    end

    -- Save to LootMaster's own award log (for undo / ML reference)
    local awardHistory = BRutus.CoreManager and BRutus.CoreManager:GetAwardHistory()
                         or (BRutus.db.lootMaster and BRutus.db.lootMaster.awardHistory) or {}
    table.insert(awardHistory, 1, {
        link = itemLink,
        itemId = itemId,
        player = playerName,
        timestamp = GetServerTime(),
        received = awarded,
    })
    while #awardHistory > 200 do
        table.remove(awardHistory)
    end

    -- Record to the central loot history (ML-awarded items only, officer action)
    if BRutus.LootTracker then
        local itemName = GetItemInfo(itemLink)
        BRutus.LootTracker:RecordMLAward({
            itemLink   = itemLink,
            itemName   = itemName or "",
            quality    = itemQuality,
            player     = playerName,
            playerKey  = playerName .. "-" .. realm,
            count      = 1,
            timestamp  = GetServerTime(),
            raid       = raidName,
            instanceID = instanceID,
            fromML     = true,
        })
    end

    -- DKP: charge the winner when the guild runs the points system and a
    -- per-item cost is configured (cost 0 = informational standings only).
    if BRutus.Points and (BRutus.GetLootSystem and BRutus:GetLootSystem()) == "dkp" and BRutus:IsOfficer() then
        local _pdb = BRutus.Points and BRutus.Points:GetDB()
        local cost = (_pdb and _pdb.config and _pdb.config.itemCost) or 0
        if cost > 0 then
            local pKey = BRutus:GetPlayerKey(playerName, realm)
            BRutus.Points:Charge(pKey, cost, GetItemInfo(itemLink) or itemLink)
            self:SafeSendChat(string.format(L["[DKP] %s charged %d points for %s"],
                playerName, cost, itemLink), "RAID")
        end
    end

    if awarded then
        BRutus:Print(itemLink .. L[" given to |cff00ff00"] .. playerName .. "|r")
    else
        BRutus:Print(itemLink .. L[" awarded to |cff00ff00"] .. playerName .. L["|r - trade to deliver."])
    end

    if self.activeLoot then self.activeLoot.delivered = true end
    self.activeLoot = nil
    self.rolls = {}
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
    BRutus:Print(string.format(L["|cffFFFF00Trade queued:|r %s for %s. Open trade with them."], itemLink, playerName))
end

-- Find an item in bags by itemId
function LootMaster:FindItemInBags(itemId)
    for bag = 0, 4 do
        local numSlots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)
            or GetContainerNumSlots and GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemId then
                return bag, slot
            else
                -- Fallback for older API
                if GetContainerItemInfo then
                    local link = select(7, GetContainerItemInfo(bag, slot))
                    if link then
                        local id = tonumber(link:match("item:(%d+)"))
                        if id == itemId then
                            return bag, slot
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

-- When trade window opens, try to auto-add pending items
function LootMaster:OnTradeShow()
    local tradeName = UnitName("NPC") or GetUnitName("NPC", false)
    if not tradeName then
        -- Try TradeFrame target
        tradeName = TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText()
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
                if C_Container and C_Container.UseContainerItem then
                    C_Container.UseContainerItem(bag, slot)
                elseif UseContainerItem then
                    UseContainerItem(bag, slot)
                end
                BRutus:Print(string.format(L["|cff00ff00Auto-added:|r %s to trade."], pending.link))
                pending.addedToTrade = true
                itemsAdded = itemsAdded + 1
                tradeSlot = tradeSlot + 1
            end
        end
    end

    if itemsAdded > 0 then
        BRutus:Print(string.format(L["%d item(s) added to trade with %s."], itemsAdded, tradeName))
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
                local _ah = BRutus.CoreManager and BRutus.CoreManager:GetAwardHistory()
                            or (BRutus.db.lootMaster and BRutus.db.lootMaster.awardHistory) or {}
                for _, award in ipairs(_ah) do
                    if award.itemId == pending.itemId
                        and award.player == pending.player
                        and not award.received then
                        award.received = true
                        break
                    end
                end
                BRutus:Print(string.format(L["|cff00ff00Trade complete:|r %s delivered to %s."], pending.link, pending.player))
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
    local dur = self.ROLL_DURATION
    local warnings = { 10, 5, 3, 2, 1 }
    for _, t in ipairs(warnings) do
        if dur > t then
            local secs = t  -- capture for closure
            C_Timer.After(dur - secs, function()
                if LootMaster.activeLoot and not LootMaster.activeLoot.ended then
                    LootMaster:SafeSendChat(
                        L["[Roll] "] .. secs .. L[" second"] .. (secs == 1 and "" or L["s"]) .. "!",
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
    if self.rollTimer then
        self.rollTimer:Cancel()
        self.rollTimer = nil
    end
    if self.activeLoot then
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
-- UI: Roll popup for raiders — shown on ANNOUNCE (BRutus ML session only).
-- Displays the item link, the local player's own prio/wishlist
-- position, and the full priority list so everyone can see who
-- has priority without having to ask.
----------------------------------------------------------------------
function LootMaster:ShowRollPopup(itemLink, duration, itemId)
    local C      = BRutus.Colors
    local myName = UnitName("player")

    if self.rollPopup then
        self.rollPopup:Hide()
    end

    ----------------------------------------------------------------
    -- Build combined priority list: officer prios first, then wishlist
    ----------------------------------------------------------------
    local entries  = {}
    local entrySet = {}  -- track names already added (deduplicate)

    -- 1. Officer prios (from db.lootPrios)
    if itemId and itemId > 0 and BRutus.db and BRutus.db.lootPrios then
        local prioList = BRutus.db.lootPrios[itemId]
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
    if itemId and itemId > 0 and BRutus.Wishlist then
        local interest = BRutus.Wishlist:GetItemInterest(itemId)
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
        local name = UnitName(unit)
        if name then
            inGroup[strlower(name)] = select(2, UnitClass(unit)) or "UNKNOWN"
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
    local f = CreateFrame("Frame", "BRutusRollPopup", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.082, 0.082, 0.105, 0.95)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    BRutus.UI:StylePopup(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText(L["Guild OS Loot Master"])

    -- Item link
    local itemText = f:CreateFontString(nil, "OVERLAY")
    itemText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    itemText:SetPoint("TOP", 0, -26)
    itemText:SetText(itemLink or L["Unknown Item"])

    -- Player's own prio / wishlist status
    local tmbText = f:CreateFontString(nil, "OVERLAY")
    tmbText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    tmbText:SetPoint("TOP", 0, -44)
    tmbText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)

    if itemId and itemId > 0 then
        local myPrioOrder = nil
        if BRutus.db and BRutus.db.lootPrios and BRutus.db.lootPrios[itemId] then
            for idx, e in ipairs(BRutus.db.lootPrios[itemId]) do
                if strlower(e.name or "") == strlower(myName) then
                    myPrioOrder = idx
                    break
                end
            end
        end

        if myPrioOrder then
            tmbText:SetText(format(L["|cffFFD700[OFFICIAL PRIO #%d]|r"], myPrioOrder))
        else
            local interest = BRutus.Wishlist and BRutus.Wishlist:GetItemInterest(itemId)
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
            h:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
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
            idxT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            idxT:SetPoint("LEFT", 4, 0)
            idxT:SetTextColor(
                e.inRaid and C.gold.r or 0.35,
                e.inRaid and C.gold.g or 0.35,
                e.inRaid and C.gold.b or 0.35)
            idxT:SetText(idx)

            -- TYPE (PRIO / WISH)
            local typeT = row:CreateFontString(nil, "OVERLAY")
            typeT:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
            typeT:SetPoint("LEFT", 18, 0)
            local tc = e.typeCat == "prio" and C.accent or C.gold
            typeT:SetTextColor(
                e.inRaid and tc.r or tc.r * 0.5,
                e.inRaid and tc.g or tc.g * 0.5,
                e.inRaid and tc.b or tc.b * 0.5)
            typeT:SetText(e.typeStr)

            -- Order (#N)
            local ordT = row:CreateFontString(nil, "OVERLAY")
            ordT:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
            ordT:SetPoint("LEFT", 60, 0)
            ordT:SetTextColor(
                e.inRaid and 0.65 or 0.3,
                e.inRaid and 0.65 or 0.3,
                e.inRaid and 0.65 or 0.3)
            ordT:SetText("#" .. e.order)

            -- Name (class-colored when in group / is self)
            local nameT = row:CreateFontString(nil, "OVERLAY")
            nameT:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            nameT:SetPoint("LEFT", 92, 0)
            nameT:SetWidth(134)
            if e.inRaid or isMe then
                local cr, cg, cb = BRutus:GetClassColor(e.class)
                nameT:SetTextColor(cr, cg, cb)
            else
                nameT:SetTextColor(0.4, 0.4, 0.4)
            end
            nameT:SetText(e.name)

            -- ATT% (25-man attendance)
            local attCtx = self:GetPlayerContext(e.name)
            local attT   = row:CreateFontString(nil, "OVERLAY")
            attT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
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
            recvT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
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
            raidT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
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
            moreT:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            moreT:SetPoint("TOPLEFT", 12, listY - 2)
            moreT:SetTextColor(0.5, 0.5, 0.5)
            moreT:SetText(format(L["+ %d more interested"], numEntries - MAX_VISIBLE))
        end
    else
        -- No wishlist/prio data for this item
        local noDataT = f:CreateFontString(nil, "OVERLAY")
        noDataT:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
        noDataT:SetPoint("TOPLEFT", 12, listY - 4)
        noDataT:SetTextColor(0.5, 0.5, 0.5)
        noDataT:SetText(L["No wishlist data for this item."])
    end

    ----------------------------------------------------------------
    -- Roll buttons (MS / OS / Pass)
    ----------------------------------------------------------------
    local UI = BRutus.UI
    local msBtn = UI:CreateButton(f, "MS", 90, 26)
    msBtn:SetPoint("BOTTOMLEFT", 15, 12)
    msBtn:SetBackdropColor(0.0, 0.4, 0.0, 0.6)
    msBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)
        f:Hide()
        BRutus:Print(L["Rolled |cff00ff00MS|r on "] .. (itemLink or L["item"]) .. " — /roll 1-100")
    end)

    local osBtn = UI:CreateButton(f, "OS", 90, 26)
    osBtn:SetPoint("BOTTOM", 0, 12)
    osBtn:SetBackdropColor(0.3, 0.3, 0.0, 0.6)
    osBtn:SetScript("OnClick", function()
        RandomRoll(1, 99)
        f:Hide()
        BRutus:Print(L["Rolled |cffFFFF00OS|r on "] .. (itemLink or L["item"]) .. " — /roll 1-99")
    end)

    local passBtn = UI:CreateButton(f, L["Pass"], 90, 26)
    passBtn:SetPoint("BOTTOMRIGHT", -15, 12)
    passBtn:SetBackdropColor(0.4, 0.0, 0.0, 0.6)
    passBtn:SetScript("OnClick", function()
        f:Hide()
    end)

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
    warnText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
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
        link      = link,
        slot      = slot,
        itemId    = itemId,
        startTime = GetServerTime(),
        endTime   = GetServerTime(),
    }
    self.rolls = {}
end

----------------------------------------------------------------------
-- UI: Loot frame for ML — auto-opens on boss kill, shows wishlist priority
-- per item; officer can award directly or open a roll for tied players.
----------------------------------------------------------------------
function LootMaster:ShowLootFrame(items)
    local C  = BRutus.Colors
    local UI = BRutus.UI

    if self.lootFrame then self.lootFrame:Hide() end

    local FRAME_W = 680
    local FRAME_H = 440
    local LEFT_W  = 178
    local RIGHT_X = LEFT_W + 12
    local rightW  = FRAME_W - LEFT_W - 22

    local f = CreateFrame("Frame", "BRutusMLLootFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.97)
    f:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(f)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Title
    local titleText = f:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    titleText:SetPoint("TOPLEFT", 12, -10)
    titleText:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    titleText:SetText(L["Master Loot"])

    -- Instance name
    local instText = f:CreateFontString(nil, "OVERLAY")
    instText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    instText:SetPoint("TOPLEFT", 132, -12)
    instText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    local instName = GetInstanceInfo and (select(1, GetInstanceInfo())) or ""
    instText:SetText((instName and instName ~= "") and ("— " .. instName) or "")

    -- Close
    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Title separator
    local titleSep = f:CreateTexture(nil, "ARTWORK")
    titleSep:SetTexture("Interface\\Buttons\\WHITE8x8")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT",  8, -26)
    titleSep:SetPoint("TOPRIGHT", -8, -26)
    titleSep:SetVertexColor(C.accent.r, C.accent.g, C.accent.b, 0.4)

    -- Vertical divider between left and right
    local vDiv = f:CreateTexture(nil, "ARTWORK")
    vDiv:SetTexture("Interface\\Buttons\\WHITE8x8")
    vDiv:SetWidth(1)
    vDiv:SetPoint("TOPLEFT",    LEFT_W + 4, -28)
    vDiv:SetPoint("BOTTOMLEFT", LEFT_W + 4, 42)
    vDiv:SetVertexColor(C.border.r, C.border.g, C.border.b, 0.5)

    ----------------------------------------------------------------
    -- Disenchanter selector (title bar, right of instance name)
    ----------------------------------------------------------------

    -- ">" button that opens the raid-member picker popup
    local dePickBtn = UI:CreateButton(f, ">", 22, 18)
    dePickBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -7)

    -- Current DE name shown inline
    local deNameText = f:CreateFontString(nil, "OVERLAY")
    deNameText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    deNameText:SetPoint("RIGHT", dePickBtn, "LEFT", -4, 1)
    deNameText:SetWidth(120)
    deNameText:SetJustifyH("LEFT")

    -- Static "DE:" label
    local deTitleLabel = f:CreateFontString(nil, "OVERLAY")
    deTitleLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    deTitleLabel:SetPoint("RIGHT", deNameText, "LEFT", -3, 0)
    deTitleLabel:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    deTitleLabel:SetText(L["DE:"])

    -- Popup frame (child of f so it auto-hides with it)
    local dePickerPopup = CreateFrame("Frame", nil, f, "BackdropTemplate")
    dePickerPopup:SetSize(170, 280)
    dePickerPopup:SetFrameStrata("DIALOG")
    dePickerPopup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dePickerPopup:SetBackdropColor(0.060, 0.060, 0.080, 0.98)
    dePickerPopup:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, C.border.a)
    UI:StylePopup(dePickerPopup, { shadowSize = 10 })
    dePickerPopup:Hide()

    -- Popup header
    local dePopHdr = dePickerPopup:CreateFontString(nil, "OVERLAY")
    dePopHdr:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    dePopHdr:SetPoint("TOPLEFT", 6, -4)
    dePopHdr:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    dePopHdr:SetText(L["DISENCHANTER"])

    -- Scroll frame inside popup
    local dePopScroll = CreateFrame("ScrollFrame", "BRutusMLDEPickerScroll", dePickerPopup, "UIPanelScrollFrameTemplate")
    dePopScroll:SetPoint("TOPLEFT",     4, -16)
    dePopScroll:SetPoint("BOTTOMRIGHT", -4, 4)
    UI:SkinScrollBar(dePopScroll, "BRutusMLDEPickerScroll")

    local dePopContent = CreateFrame("Frame", nil, dePopScroll)
    dePopContent:SetWidth(140)
    dePopContent:SetHeight(1)
    dePopScroll:SetScrollChild(dePopContent)

    -- Refresh the "DE: <name>" text in the title bar
    local function RefreshDELabel()
        local deName = LootMaster:GetDisenchanter()
        if deName and deName ~= "" then
            deNameText:SetTextColor(0.3, 1.0, 0.3)
            deNameText:SetText(deName)
        else
            deNameText:SetTextColor(0.45, 0.45, 0.45)
            deNameText:SetText(L["None"])
        end
    end
    RefreshDELabel()

    -- Rebuild the popup rows from the current raid roster
    local function BuildAndShowDEPicker()
        -- Clear old member rows (preserves header + scroll frame)
        for _, ch in ipairs({ dePopContent:GetChildren() }) do ch:Hide() end
        for _, rg in ipairs({ dePopContent:GetRegions() }) do rg:Hide() end

        -- Collect raid / party members
        local members = {}
        local numMembers = GetNumGroupMembers()
        if numMembers > 0 then
            for i = 1, numMembers do
                local unit = (IsInRaid() and ("raid" .. i)) or ("party" .. i)
                local name = UnitName(unit)
                if name then
                    local class = select(2, UnitClass(unit)) or "UNKNOWN"
                    table.insert(members, { name = name, class = class })
                end
            end
        end
        -- In testMode (or outside a group) include the local player
        if LootMaster.testMode or numMembers == 0 then
            local myName  = UnitName("player")
            local myClass = select(2, UnitClass("player")) or "UNKNOWN"
            if myName then
                local found = false
                for _, m in ipairs(members) do
                    if m.name == myName then found = true; break end
                end
                if not found then
                    table.insert(members, { name = myName, class = myClass })
                end
            end
        end

        table.sort(members, function(a, b) return a.name < b.name end)

        local ROW_H = 20
        local rowW  = math.max(10, dePopContent:GetWidth() - 2)
        local yOff  = 0
        local curDE = LootMaster:GetDisenchanter()

        for _, m in ipairs(members) do
            local isSelected = (m.name == curDE)
            local row = CreateFrame("Button", nil, dePopContent, "BackdropTemplate")
            row:SetSize(rowW, ROW_H)
            row:SetPoint("TOPLEFT", 0, -yOff)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor(
                isSelected and 0.14 or 0,
                isSelected and 0.10 or 0,
                isSelected and 0.26 or 0,
                isSelected and 1    or 0)

            local cr, cg, cb = BRutus:GetClassColor(m.class)
            local rowText = row:CreateFontString(nil, "OVERLAY")
            rowText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            rowText:SetPoint("LEFT", 6, 0)
            rowText:SetTextColor(cr, cg, cb)
            rowText:SetText(m.name)

            local capturedName = m.name
            row:SetScript("OnClick", function()
                LootMaster:SetDisenchanter(capturedName)
                RefreshDELabel()
                dePickerPopup:Hide()
                BRutus:Print(L["Disenchanter: |cff00ff00"] .. capturedName .. "|r")
            end)
            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end)
            row:SetScript("OnLeave", function(self)
                if LootMaster:GetDisenchanter() == capturedName then
                    self:SetBackdropColor(0.160, 0.150, 0.220, 1)
                else
                    self:SetBackdropColor(0, 0, 0, 0)
                end
            end)
            yOff = yOff + ROW_H + 1
        end

        -- "— Nenhum —" clears the current selection
        local clearRow = CreateFrame("Button", nil, dePopContent, "BackdropTemplate")
        clearRow:SetSize(rowW, ROW_H)
        clearRow:SetPoint("TOPLEFT", 0, -yOff)
        clearRow:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        clearRow:SetBackdropColor(0, 0, 0, 0)
        local clearText = clearRow:CreateFontString(nil, "OVERLAY")
        clearText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        clearText:SetPoint("LEFT", 6, 0)
        clearText:SetTextColor(0.4, 0.4, 0.4)
        clearText:SetText(L["--- None ---"])
        clearRow:SetScript("OnClick", function()
            LootMaster:SetDisenchanter("")
            RefreshDELabel()
            dePickerPopup:Hide()
        end)
        clearRow:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
        end)
        clearRow:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
        end)
        yOff = yOff + ROW_H + 1

        dePopContent:SetHeight(math.max(1, yOff))

        -- Anchor popup below the ">" button
        dePickerPopup:ClearAllPoints()
        dePickerPopup:SetPoint("TOPRIGHT", dePickBtn, "BOTTOMRIGHT", 0, -2)
        dePickerPopup:Show()
    end

    dePickBtn:SetScript("OnClick", function()
        if dePickerPopup:IsShown() then
            dePickerPopup:Hide()
        else
            BuildAndShowDEPicker()
        end
    end)

    ----------------------------------------------------------------
    -- Left panel: items list
    ----------------------------------------------------------------
    local itemsLabel = f:CreateFontString(nil, "OVERLAY")
    itemsLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    itemsLabel:SetPoint("TOPLEFT", 8, -30)
    itemsLabel:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
    itemsLabel:SetText(L["LOOT  ("] .. #items .. ")")

    local selectedBtn  = nil
    local selectedItem = nil
    local itemBtns     = {}

    ----------------------------------------------------------------
    -- Right panel: selected item header + column headers
    ----------------------------------------------------------------
    local selItemText = f:CreateFontString(nil, "OVERLAY")
    selItemText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    selItemText:SetPoint("TOPLEFT", RIGHT_X, -30)
    selItemText:SetWidth(rightW - 10)
    selItemText:SetJustifyH("LEFT")
    selItemText:SetText(L["|cff888888Select an item from the left.|r"])

    -- Column headers
    local prioHdr = CreateFrame("Frame", nil, f, "BackdropTemplate")
    prioHdr:SetSize(rightW, 16)
    prioHdr:SetPoint("TOPLEFT", RIGHT_X, -52)
    prioHdr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    prioHdr:SetBackdropColor(0.040, 0.040, 0.055, 1)
    local function PH(txt, x)
        local t = prioHdr:CreateFontString(nil, "OVERLAY")
        t:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        t:SetPoint("LEFT", x, 0)
        t:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
        t:SetText(txt)
    end
    PH("#", 4); PH(L["TYPE"], 22); PH(L["ORDER"], 64); PH(L["PLAYER"], 106); PH(L["ATT%"], 210); PH(L["RECV"], 255); PH(L["IN RAID"], 295)

    -- Priority scroll area
    local prioContainer = CreateFrame("Frame", nil, f)
    prioContainer:SetPoint("TOPLEFT",     RIGHT_X, -70)
    prioContainer:SetPoint("BOTTOMRIGHT", -8,       42)

    local prioScroll = CreateFrame("ScrollFrame", "BRutusMLPrioScroll", prioContainer, "UIPanelScrollFrameTemplate")
    prioScroll:SetPoint("TOPLEFT",     0, 0)
    prioScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    UI:SkinScrollBar(prioScroll, "BRutusMLPrioScroll")

    local prioChild = CreateFrame("Frame", nil, prioScroll)
    prioChild:SetWidth(rightW - 20)
    prioChild:SetHeight(1)
    prioScroll:SetScrollChild(prioChild)

    prioContainer:SetScript("OnSizeChanged", function(self)
        prioChild:SetWidth(math.max(1, self:GetWidth() - 20))
    end)

    -- Bottom row: status text + Roll + Award buttons
    local statusText = f:CreateFontString(nil, "OVERLAY")
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    statusText:SetPoint("BOTTOMLEFT", RIGHT_X, 14)
    statusText:SetWidth(rightW - 290)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")

    local awardTopBtn = UI:CreateButton(f, L["Award #1"], 140, 26)
    awardTopBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    awardTopBtn:Disable()

    local openRollBtn = UI:CreateButton(f, L["Open Roll"], 120, 26)
    openRollBtn:SetPoint("RIGHT", awardTopBtn, "LEFT", -6, 0)

    -- Send to disenchanter (for items nobody wants)
    local deLootBtn = UI:CreateButton(f, L["Send to DE"], 110, 26)
    deLootBtn:SetPoint("RIGHT", openRollBtn, "LEFT", -6, 0)
    deLootBtn:SetBackdropColor(0.260, 0.160, 0.360, 0.7)
    deLootBtn:SetScript("OnClick", function()
        if not selectedItem then
            statusText:SetText(L["|cffFF4444Select an item first.|r"])
            return
        end
        local iId = tonumber(selectedItem.link:match("item:(%d+)"))
        LootMaster:SetActiveLoot(selectedItem.link, selectedItem.slot, iId)
        LootMaster:SendToDisenchanter(selectedItem.link, selectedItem.slot, iId)
        statusText:SetText(L["|cff9966FFSent to Disenchant!|r"])
        if itemBtns[selectedItem.slot] then
            itemBtns[selectedItem.slot].awardedText:Show()
        end
    end)
    deLootBtn:SetScript("OnEnter", function(self)
        local deName = LootMaster:GetDisenchanter()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if deName and deName ~= "" then
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cff00ff00" .. deName .. "|r", 1, 1, 1)
        else
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cffFF4444" .. L["No disenchanter set"] .. "|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    deLootBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local topCandidate = nil
    local tiedCount    = 0

    ----------------------------------------------------------------
    -- Helper: build raid-member name→class lookup
    ----------------------------------------------------------------
    local function BuildRaidMap()
        local map = {}
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            local name = UnitName(unit)
            if name then
                map[strlower(name)] = select(2, UnitClass(unit)) or "UNKNOWN"
            end
        end
        local myName = UnitName("player")
        if myName then
            map[strlower(myName)] = select(2, UnitClass("player")) or "UNKNOWN"
        end
        return map
    end

    ----------------------------------------------------------------
    -- Helper: do the award + UI update
    ----------------------------------------------------------------
    local function DoAward(item, entryName)
        local iId = tonumber(item.link:match("item:(%d+)"))
        LootMaster:SetActiveLoot(item.link, item.slot, iId)
        LootMaster:AwardLoot(entryName)  -- RecordReceived is called inside AwardLoot
        statusText:SetText(L["|cff4CFF4CAwarded to "] .. entryName .. "!|r")
        if itemBtns[item.slot] then
            itemBtns[item.slot].awardedText:Show()
        end
    end

    ----------------------------------------------------------------
    -- Load priority list for a selected item
    ----------------------------------------------------------------
    local function LoadItem(item)
        selectedItem = item
        topCandidate = nil
        tiedCount    = 0
        statusText:SetText("")

        selItemText:SetText(item.link)

        -- Clear previous list
        for _, ch in ipairs({ prioChild:GetChildren() }) do ch:Hide() end
        for _, rg in ipairs({ prioChild:GetRegions() }) do rg:Hide() end

        local itemId = tonumber(item.link:match("item:(%d+)"))

        local function NoData(msg)
            local t = prioChild:CreateFontString(nil, "OVERLAY")
            t:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            t:SetPoint("TOPLEFT", 6, -14)
            t:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
            t:SetText(msg)
            prioChild:SetHeight(40)
            awardTopBtn:SetText(L["Award #1"])
            awardTopBtn:Disable()
            openRollBtn:SetText(L["Roll for All"])
        end

        if not itemId then
            NoData(L["Could not parse item ID."])
            return
        end

        -- Full wishlist interest list
        local interest = BRutus.Wishlist and BRutus.Wishlist:GetItemInterest(itemId) or nil
        local candidates = {}
        if interest then
            for _, e in ipairs(interest) do
                table.insert(candidates, e)
            end
        end

        if #candidates == 0 then
            NoData(L["No wishlist data for this item - use Open Roll."])
            return
        end

        local raidMap = BuildRaidMap()

        -- Find first in-raid candidate (candidates already sorted prio→wish→order)
        for _, e in ipairs(candidates) do
            if raidMap[strlower(e.name)] then
                if not topCandidate then topCandidate = e end
            end
        end

        -- Count how many share the exact same top tier
        if topCandidate then
            for _, e in ipairs(candidates) do
                if raidMap[strlower(e.name)]
                    and e.type  == topCandidate.type
                    and e.order == topCandidate.order then
                    tiedCount = tiedCount + 1
                end
            end
        end

        -- Update bottom buttons
        if topCandidate then
            if tiedCount == 1 then
                awardTopBtn:SetText(L["Award → "] .. topCandidate.name)
                awardTopBtn:Enable()
                openRollBtn:SetText(L["Open Roll"])
            else
                awardTopBtn:SetText(format(L["Tied %d — Roll"], tiedCount))
                awardTopBtn:Disable()
                openRollBtn:SetText(format(L["Roll Tied (%d)"], tiedCount))
            end
        else
            awardTopBtn:SetText(L["Award #1"])
            awardTopBtn:Disable()
            openRollBtn:SetText(L["Roll for All"])
        end

        -- Render priority rows
        local yOff = 0
        local rowW = math.max(10, prioChild:GetWidth())
        if rowW < 10 then rowW = rightW - 24 end

        for idx, e in ipairs(candidates) do
            local isPresent = raidMap[strlower(e.name)] ~= nil
            local isTopTier = topCandidate
                and e.type  == topCandidate.type
                and e.order == topCandidate.order
            local rowH = 22

            local row = CreateFrame("Frame", nil, prioChild, "BackdropTemplate")
            row:SetSize(rowW, rowH)
            row:SetPoint("TOPLEFT", 0, -yOff)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

            local bg = (idx % 2 == 1) and C.row1 or C.row2
            local bgA = isPresent and (bg.a or 1) or (bg.a or 1) * 0.4

            if isTopTier and isPresent then
                row:SetBackdropColor(0.100, 0.100, 0.140, 1.0)
                -- accent bar on left edge
                local bar = row:CreateTexture(nil, "ARTWORK")
                bar:SetTexture("Interface\\Buttons\\WHITE8x8")
                bar:SetPoint("TOPLEFT",    0, 0)
                bar:SetPoint("BOTTOMLEFT", 0, 0)
                bar:SetWidth(3)
                local tc = e.type == "prio" and C.accent or C.gold
                bar:SetVertexColor(tc.r, tc.g, tc.b, 0.9)
            else
                row:SetBackdropColor(bg.r, bg.g, bg.b, bgA)
            end

            -- Column: index
            local idxT = row:CreateFontString(nil, "OVERLAY")
            idxT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            idxT:SetPoint("LEFT", 4, 0)
            idxT:SetText(idx)
            idxT:SetTextColor(
                isPresent and C.gold.r or 0.35,
                isPresent and C.gold.g or 0.35,
                isPresent and C.gold.b or 0.35)

            -- Column: type
            local typeT = row:CreateFontString(nil, "OVERLAY")
            typeT:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
            typeT:SetPoint("LEFT", 22, 0)
            typeT:SetText(e.type == "prio" and L["PRIO"] or L["WISH"])
            local tc2 = e.type == "prio" and C.accent or C.gold
            typeT:SetTextColor(
                isPresent and tc2.r or 0.3,
                isPresent and tc2.g or 0.3,
                isPresent and tc2.b or 0.3)

            -- Column: order
            local ordT = row:CreateFontString(nil, "OVERLAY")
            ordT:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
            ordT:SetPoint("LEFT", 64, 0)
            ordT:SetText("#" .. (e.order or "?"))
            ordT:SetTextColor(
                isPresent and 0.65 or 0.3,
                isPresent and 0.65 or 0.3,
                isPresent and 0.65 or 0.3)

            -- Column: player name (class-colored if in raid)
            local nameT = row:CreateFontString(nil, "OVERLAY")
            nameT:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            nameT:SetPoint("LEFT", 106, 0)
            nameT:SetWidth(100)
            if isPresent then
                local rClass = raidMap[strlower(e.name)]
                local cr, cg, cb = BRutus:GetClassColor(rClass or e.class)
                nameT:SetTextColor(cr, cg, cb)
            else
                nameT:SetTextColor(0.4, 0.4, 0.4)
            end
            nameT:SetText(e.name)

            -- Column: ATT% (25-man attendance)
            local attCtx = LootMaster:GetPlayerContext(e.name)
            local attT = row:CreateFontString(nil, "OVERLAY")
            attT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            attT:SetPoint("LEFT", 210, 0)
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

            -- Column: RECV (items received this lockout)
            local recvT = row:CreateFontString(nil, "OVERLAY")
            recvT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            recvT:SetPoint("LEFT", 255, 0)
            recvT:SetWidth(35)
            recvT:SetJustifyH("CENTER")
            if attCtx.recvThisLockout == 0 then
                recvT:SetTextColor(0.4, 0.4, 0.4)
            elseif attCtx.recvThisLockout == 1 then
                recvT:SetTextColor(1.0, 1.0, 0.3)
            else
                recvT:SetTextColor(1.0, 0.3, 0.3)
            end
            recvT:SetText(tostring(attCtx.recvThisLockout))

            -- Column: in-raid indicator
            local raidT = row:CreateFontString(nil, "OVERLAY")
            raidT:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            raidT:SetPoint("LEFT", 295, 0)
            if isPresent then
                raidT:SetTextColor(0.3, 1.0, 0.3)
                raidT:SetText(L["IN RAID"])
            else
                raidT:SetTextColor(0.4, 0.4, 0.4)
                raidT:SetText(L["absent"])
            end

            -- Award button (in-raid + ML only)
            if isPresent and LootMaster:IsMasterLooter() then
                local aBtn = UI:CreateButton(row, L["Award"], 58, 18)
                aBtn:SetPoint("RIGHT", -4, 0)
                local capturedEntry = e
                local capturedItem  = item
                aBtn:SetScript("OnClick", function()
                    DoAward(capturedItem, capturedEntry.name)
                    C_Timer.After(0.3, function()
                        if selectedItem == capturedItem then
                            LoadItem(capturedItem)
                        end
                    end)
                end)
            end

            -- Row hover
            local capturedBg   = bg
            local capturedBgA  = bgA
            local capturedTop  = isTopTier and isPresent
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            end)
            row:SetScript("OnLeave", function(self)
                if capturedTop then
                    self:SetBackdropColor(0.100, 0.100, 0.140, 1.0)
                else
                    self:SetBackdropColor(capturedBg.r, capturedBg.g, capturedBg.b, capturedBgA)
                end
            end)

            yOff = yOff + rowH + 2
        end

        -- "Already received by" section
        if interest then
            local recvList = {}
            for _, e in ipairs(interest) do
                if e.type == "received" then table.insert(recvList, e) end
            end
            if #recvList > 0 then
                yOff = yOff + 6
                local recvHdr = prioChild:CreateFontString(nil, "OVERLAY")
                recvHdr:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                recvHdr:SetPoint("TOPLEFT", 4, -yOff)
                recvHdr:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
                recvHdr:SetText(L["Already received:"])
                yOff = yOff + 16
                for _, e in ipairs(recvList) do
                    local rt = prioChild:CreateFontString(nil, "OVERLAY")
                    rt:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
                    rt:SetPoint("TOPLEFT", 12, -yOff)
                    rt:SetTextColor(0.5, 0.5, 0.5)
                    rt:SetText(e.name .. (e.receivedAt and " (" .. e.receivedAt .. ")" or ""))
                    yOff = yOff + 16
                end
            end
        end

        prioChild:SetHeight(math.max(1, yOff + 8))
    end

    ----------------------------------------------------------------
    -- Left panel: one button per loot item
    ----------------------------------------------------------------
    local leftYOff = 46
    for _, item in ipairs(items) do
        local btn = CreateFrame("Button", nil, f, "BackdropTemplate")
        btn:SetSize(LEFT_W - 10, 32)
        btn:SetPoint("TOPLEFT", 5, -leftYOff)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0.090, 0.090, 0.115, 0.7)
        btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 0.3)

        -- Quality-colored item name
        local qc = BRutus.QualityColors[item.quality] or BRutus.QualityColors[4]
        local nameT = btn:CreateFontString(nil, "OVERLAY")
        nameT:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        nameT:SetPoint("TOPLEFT", 6, -4)
        nameT:SetWidth(LEFT_W - 24)
        nameT:SetJustifyH("LEFT")
        nameT:SetTextColor(qc.r, qc.g, qc.b)
        nameT:SetText(item.name or item.link)

        -- "✓ awarded" badge (hidden initially)
        local aText = btn:CreateFontString(nil, "OVERLAY")
        aText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
        aText:SetPoint("BOTTOMLEFT", 6, 3)
        aText:SetTextColor(0.3, 1.0, 0.3)
        aText:SetText(L["awarded"])
        aText:Hide()
        btn.awardedText = aText

        -- Tooltip
        local capturedItem = item
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetHyperlink(capturedItem.link)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            if selectedItem == capturedItem then
                self:SetBackdropColor(0.180, 0.160, 0.250, 0.9)
            else
                self:SetBackdropColor(0.090, 0.090, 0.115, 0.7)
            end
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if selectedBtn then
                selectedBtn:SetBackdropColor(0.090, 0.090, 0.115, 0.7)
            end
            selectedBtn = self
            self:SetBackdropColor(0.180, 0.160, 0.250, 0.9)
            LoadItem(capturedItem)
        end)

        itemBtns[item.slot] = btn
        leftYOff = leftYOff + 34
    end

    -- Wishlist Council toggle (bottom-left)
    local tmbCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    tmbCheck:SetSize(22, 22)
    tmbCheck:SetPoint("BOTTOMLEFT", 5, 14)
    tmbCheck:SetChecked(self.WISHLIST_ONLY_MODE)
    tmbCheck:SetScript("OnClick", function(cb)
        local val = cb:GetChecked()
        LootMaster.WISHLIST_ONLY_MODE = val
        LootMaster:SaveCfgKey("wishlistOnlyMode", val)
    end)
    local tmbLabel = f:CreateFontString(nil, "OVERLAY")
    tmbLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    tmbLabel:SetPoint("LEFT", tmbCheck, "RIGHT", 2, 0)
    tmbLabel:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    tmbLabel:SetText(L["Wishlist Council"])

    ----------------------------------------------------------------
    -- Bottom button handlers
    ----------------------------------------------------------------
    awardTopBtn:SetScript("OnClick", function()
        if not topCandidate or not selectedItem then
            statusText:SetText(L["|cffFF4444No top priority candidate.|r"])
            return
        end
        DoAward(selectedItem, topCandidate.name)
        C_Timer.After(0.3, function()
            if selectedItem then LoadItem(selectedItem) end
        end)
    end)

    openRollBtn:SetScript("OnClick", function()
        if not selectedItem then
            statusText:SetText(L["|cffFF4444Select an item first.|r"])
            return
        end
        LootMaster:AnnounceItem(selectedItem.link, selectedItem.slot)
        LootMaster:ShowRollFrame()
        statusText:SetText(L["|cffFFFF00Roll opened!|r"])
    end)

    ----------------------------------------------------------------
    -- Auto-select first item
    ----------------------------------------------------------------
    if #items > 0 then
        local firstBtn = itemBtns[items[1].slot]
        if firstBtn then
            selectedBtn = firstBtn
            firstBtn:SetBackdropColor(0.180, 0.160, 0.250, 0.9)
        end
        LoadItem(items[1])
    end

    f:Show()
    self.lootFrame = f
end

----------------------------------------------------------------------
-- UI: Roll tracking frame for ML
----------------------------------------------------------------------
function LootMaster:ShowRollFrame()
    local C = BRutus.Colors
    local UI = BRutus.UI

    if self.rollFrame then
        self.rollFrame:Hide()
    end

    local f = CreateFrame("Frame", "BRutusMLRollFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 350)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.058, 0.058, 0.075, 0.95)
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
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
    title:SetText(L["Roll Tracker"])

    -- Item display
    local itemText = f:CreateFontString(nil, "OVERLAY")
    itemText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    itemText:SetPoint("TOP", 0, -28)
    f.itemText = itemText

    -- Timer
    local timerText = f:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timerText:SetPoint("TOP", 0, -44)
    timerText:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    f.timerText = timerText

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetTexture("Interface\\Buttons\\WHITE8x8")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 10, -56)
    sep:SetPoint("TOPRIGHT", -10, -56)
    sep:SetVertexColor(C.border.r, C.border.g, C.border.b, 0.4)

    -- Column headers
    local headers = { { L["Player"], 6 }, { L["Type"], 145 }, { L["Roll"], 195 }, { L["Prio/WL"], 245 }, { L["ATT%"], 325 }, { L["RECV"], 375 } }
    for _, h in ipairs(headers) do
        local ht = f:CreateFontString(nil, "OVERLAY")
        ht:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        ht:SetPoint("TOPLEFT", h[2], -62)
        ht:SetTextColor(C.gold.r, C.gold.g, C.gold.b)
        ht:SetText(h[1])
    end

    -- Scroll area for rolls
    local scrollFrame = CreateFrame("ScrollFrame", "BRutusRollScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -76)
    scrollFrame:SetPoint("BOTTOMRIGHT", -10, 50)
    UI:SkinScrollBar(scrollFrame, "BRutusRollScroll")
    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(480, 1)
    scrollFrame:SetScrollChild(scrollContent)
    f.scrollContent = scrollContent

    -- Bottom buttons
    local cancelBtn = UI:CreateButton(f, L["Cancel"], 80, 24)
    cancelBtn:SetPoint("BOTTOMLEFT", 10, 12)
    cancelBtn:SetBackdropColor(C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3, 0.6)
    cancelBtn:SetScript("OnClick", function()
        LootMaster:CancelRolling()
    end)

    local endBtn = UI:CreateButton(f, L["End Rolling"], 100, 24)
    endBtn:SetPoint("BOTTOM", 0, 12)
    endBtn:SetScript("OnClick", function()
        LootMaster:EndRolling()
    end)
    f.endBtn = endBtn

    -- Send to Disenchanter (between Cancel and End Rolling)
    local deRollBtn = UI:CreateButton(f, L["Send to DE"], 100, 24)
    deRollBtn:SetPoint("LEFT", cancelBtn, "RIGHT", 8, 0)
    deRollBtn:SetBackdropColor(0.260, 0.160, 0.360, 0.7)
    deRollBtn:SetScript("OnClick", function()
        if not LootMaster.activeLoot then
            BRutus:Print(L["No active item to send to the disenchanter."])
            return
        end
        local loot = LootMaster.activeLoot
        LootMaster:SendToDisenchanter(loot.link, loot.slot, loot.itemId)
        f:Hide()
    end)
    deRollBtn:SetScript("OnEnter", function(self)
        local deName = LootMaster:GetDisenchanter()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if deName and deName ~= "" then
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cff00ff00" .. deName .. "|r", 1, 1, 1)
        else
            GameTooltip:SetText(L["Send to Disenchant"] .. "\n|cffFF4444" .. L["No disenchanter set"] .. "|r", 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    deRollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Roll buttons for the initiator (ML can also compete for the item)
    -- OS button (right-most)
    local osRollBtn = UI:CreateButton(f, "OS", 64, 24)
    osRollBtn:SetPoint("BOTTOMRIGHT", -10, 12)
    osRollBtn:SetBackdropColor(0.3, 0.3, 0.0, 0.6)
    osRollBtn:SetScript("OnClick", function()
        RandomRoll(1, 99)   -- /roll 1-99 = OS; captured by ProcessSystemRoll
    end)
    osRollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Roll Off-Spec"] .. "\n|cff888888/roll 1-99|r", 1, 1, 1)
        GameTooltip:Show()
    end)
    osRollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- MS button (left of OS)
    local msRollBtn = UI:CreateButton(f, "MS", 64, 24)
    msRollBtn:SetPoint("RIGHT", osRollBtn, "LEFT", -4, 0)
    msRollBtn:SetBackdropColor(0.0, 0.35, 0.0, 0.6)
    msRollBtn:SetScript("OnClick", function()
        RandomRoll(1, 100)  -- /roll 1-100 = MS; captured by ProcessSystemRoll
    end)
    msRollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Roll Main Spec"] .. "\n|cff888888/roll 1-100|r", 1, 1, 1)
        GameTooltip:Show()
    end)
    msRollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Roll label
    local rollLabel = f:CreateFontString(nil, "OVERLAY")
    rollLabel:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    rollLabel:SetPoint("BOTTOM", msRollBtn, "TOP", 32, 2)
    rollLabel:SetTextColor(C.silver.r, C.silver.g, C.silver.b)
    rollLabel:SetText(L["Your roll:"])

    -- Close
    local closeBtn = UI:CreateCloseButton(f)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:Show()
    self.rollFrame = f

    -- Timer ticker
    if f.ticker then f.ticker:Cancel() end
    f.ticker = C_Timer.NewTicker(1, function()
        LootMaster:UpdateRollTimer()
    end)
    f:SetScript("OnHide", function()
        if f.ticker then f.ticker:Cancel() end
        LootMaster.testMode = false
    end)

    self:RefreshRollFrame()
end

----------------------------------------------------------------------
-- Refresh the roll tracker display
----------------------------------------------------------------------
function LootMaster:RefreshRollFrame()
    if not self.rollFrame or not self.rollFrame:IsShown() then return end
    local f = self.rollFrame

    -- Update item
    if self.activeLoot then
        f.itemText:SetText(self.activeLoot.link or L["No item"])
    else
        f.itemText:SetText(L["|cff888888No active roll|r"])
        f.timerText:SetText("")
    end

    -- Clear scroll content
    local content = f.scrollContent
    for _, child in pairs({ content:GetChildren() }) do child:Hide() end

    -- Build sorted list
    local lootSystem = (BRutus.GetLootSystem and BRutus:GetLootSystem()) or "rolls"
    local sorted = {}
    for _, r in pairs(self.rolls) do
        table.insert(sorted, r)
    end
    -- Sort: MS first, then (DKP mode) highest DKP / (else) prio order, then roll
    table.sort(sorted, function(a, b)
        if a.rollType ~= b.rollType then
            if a.rollType == "PASS" then return false end
            if b.rollType == "PASS" then return true end
            return a.rollType == "MS"
        end
        if lootSystem == "dkp" then
            local ad, bd = a.dkp or 0, b.dkp or 0
            if ad ~= bd then return ad > bd end
        else
            local aPrio = a.prioOrder or 999
            local bPrio = b.prioOrder or 999
            if aPrio ~= bPrio then return aPrio < bPrio end
        end
        return a.roll > b.roll
    end)

    local CLASS_COLORS = RAID_CLASS_COLORS
    local yOff = 0
    for _, r in ipairs(sorted) do
        local row = CreateFrame("Button", nil, content, "BackdropTemplate")
        row:SetSize(480, 22)
        row:SetPoint("TOPLEFT", 0, -yOff)
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0.082, 0.082, 0.105, 0.6)

        -- Player name (class colored)
        local cc = CLASS_COLORS[r.class] or { r = 0.8, g = 0.8, b = 0.8 }
        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        nameText:SetPoint("LEFT", 6, 0)
        nameText:SetTextColor(cc.r, cc.g, cc.b)
        nameText:SetText(r.name)

        -- Roll type
        local typeText = row:CreateFontString(nil, "OVERLAY")
        typeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        typeText:SetPoint("LEFT", 150, 0)
        if r.rollType == "MS" then
            typeText:SetTextColor(0.3, 1.0, 0.3)
        elseif r.rollType == "OS" then
            typeText:SetTextColor(1.0, 1.0, 0.3)
        else
            typeText:SetTextColor(0.5, 0.5, 0.5)
        end
        typeText:SetText(r.rollType)

        -- Roll number
        local rollText = row:CreateFontString(nil, "OVERLAY")
        rollText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        rollText:SetPoint("LEFT", 200, 0)
        rollText:SetTextColor(1, 1, 1)
        rollText:SetText(r.rollType ~= "PASS" and tostring(r.roll) or "-")

        -- Prio / Wishlist info
        local tmbText = row:CreateFontString(nil, "OVERLAY")
        tmbText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        tmbText:SetPoint("LEFT", 250, 0)
        if lootSystem == "dkp" then
            tmbText:SetText(string.format(L["|cffFFD700%d DKP|r"], r.dkp or 0))
        elseif r.prioOrder then
            tmbText:SetText(string.format(L["|cffFFD700* Prio #%d|r"], r.prioOrder))
        elseif r.wishlist then
            tmbText:SetText(L["|cff4CB8FFwishlist #"] .. r.wishlist.order .. "|r")
        else
            tmbText:SetTextColor(0.4, 0.4, 0.4)
            tmbText:SetText("-")
        end

        -- ATT% (25-man attendance)
        local attText = row:CreateFontString(nil, "OVERLAY")
        attText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        attText:SetPoint("LEFT", 330, 0)
        attText:SetWidth(42)
        attText:SetJustifyH("RIGHT")
        local att25 = r.att25 or 0
        if att25 >= 60 then
            attText:SetTextColor(0.3, 1.0, 0.3)
        elseif att25 >= 40 then
            attText:SetTextColor(1.0, 1.0, 0.3)
        else
            attText:SetTextColor(1.0, 0.3, 0.3)
        end
        attText:SetText(att25 .. "%")

        -- RECV (items received this lockout)
        local recvText = row:CreateFontString(nil, "OVERLAY")
        recvText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        recvText:SetPoint("LEFT", 378, 0)
        recvText:SetWidth(32)
        recvText:SetJustifyH("CENTER")
        local recvN = r.recvCount or 0
        if recvN == 0 then
            recvText:SetTextColor(0.4, 0.4, 0.4)
        elseif recvN == 1 then
            recvText:SetTextColor(1.0, 1.0, 0.3)
        else
            recvText:SetTextColor(1.0, 0.3, 0.3)
        end
        recvText:SetText(tostring(recvN))

        -- Award button (only when rolling ended and ML)
        if self.activeLoot and self.activeLoot.ended and self:IsMasterLooter() and r.rollType ~= "PASS" then
            local awardBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            awardBtn:SetSize(50, 18)
            awardBtn:SetPoint("RIGHT", -2, 0)
            awardBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            awardBtn:SetBackdropColor(0.0, 0.3, 0.0, 0.6)
            awardBtn:SetBackdropBorderColor(0.0, 0.5, 0.0, 0.4)
            local aText = awardBtn:CreateFontString(nil, "OVERLAY")
            aText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            aText:SetPoint("CENTER")
            aText:SetText(L["Award"])
            aText:SetTextColor(0.3, 1.0, 0.3)
            local playerName = r.name
            awardBtn:SetScript("OnClick", function()
                LootMaster:AwardLoot(playerName)
                f:Hide()
            end)
            awardBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.0, 0.5, 0.0, 0.8)
            end)
            awardBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.0, 0.3, 0.0, 0.6)
            end)
        end

        yOff = yOff + 24
    end
    content:SetHeight(math.max(1, yOff))
end

----------------------------------------------------------------------
-- Update timer display
----------------------------------------------------------------------
function LootMaster:UpdateRollTimer()
    if not self.rollFrame or not self.activeLoot then return end

    if self.activeLoot.ended then
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

-- Award the active item (or the provided item) to the disenchanter.
-- Called when ML clicks "Send to DE" from any loot UI.
function LootMaster:SendToDisenchanter(itemLink, lootSlot, itemId, reason)
    local deName = self:GetDisenchanter()
    if not deName or deName == "" then
        BRutus:Print("|cffFF4444" .. L["No disenchanter set."] .. "|r " .. L["Configure it in the Loot Master options."])
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

    self:AwardLoot(deName, true)  -- silent: message already sent above
end

----------------------------------------------------------------------
-- Roll from Bag — start a full BRutus roll for an item already in
-- the ML's bags (e.g. items picked up to distribute later).
-- Awards always go through the trade path (QueueForTrade) because
-- there is no ML loot window for bag items.
----------------------------------------------------------------------
function LootMaster:RollFromBag(bag, slot)
    if not IsInRaid() and not self.testMode then
        BRutus:Print("|cffFF4444[LootMaster]|r " .. L["Only available in a raid."])
        return
    end
    if not self:IsMasterLooter() then
        BRutus:Print("|cffFF4444[LootMaster]|r " .. L["Only the Master Looter can use this function."])
        return
    end

    -- Block if a roll session is already in progress
    if self.activeLoot and not self.activeLoot.delivered then
        BRutus:Print("|cffFF9900[LootMaster]|r " .. L["Roll in progress: "] .. (self.activeLoot.link or "?"))
        return
    end

    -- Get item link from bag slot
    local itemLink
    if C_Container and C_Container.GetContainerItemLink then
        itemLink = C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then
        itemLink = GetContainerItemLink(bag, slot)  -- luacheck: ignore
    end

    if not itemLink then return end

    -- Respect the configured rarity threshold; skip if info not cached yet
    local _, _, quality = GetItemInfo(itemLink)
    if quality and quality < (self.LOOT_THRESHOLD or 3) then
        BRutus:Print("|cffFF9900[LootMaster]|r " .. L["Item below the configured rarity threshold."])
        return
    end

    -- Force trade-delivery path (no loot window is open for bag items)
    self.lootWindowOpen = false

    BRutus:Print("|cff00ff00[LootMaster]|r " .. L["Starting bag roll: "] .. itemLink)
    self:AnnounceItem(itemLink, nil)
end
