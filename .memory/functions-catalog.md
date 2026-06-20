# BRutus — Complete Function Catalog

## Config.lua — BRutus.Config (NEW — Phase 1)

| Symbol | Description |
|---|---|
| `BRutus.Config.ADDON_NAME` | "BRutus" |
| `BRutus.Config.VERSION` | mirrors BRutus.VERSION ("1.0.0") |
| `BRutus.Config.COMM_VERSION` | mirrors BRutus.COMM_VERSION (1) |
| `BRutus.Config.PREFIX` | mirrors BRutus.PREFIX ("BRutus") |
| `BRutus.Config.CHUNK_SIZE` | 230 — max bytes per addon message chunk |
| `BRutus.Config.BROADCAST_THROTTLE` | 5 — min seconds between broadcasts |
| `BRutus.Config.SYNC_TICKER_INTERVAL` | 300 — periodic sync interval (s) |
| `BRutus.Config.INIT_REQUEST_DELAY` | 8 — seconds before requesting guild data |
| `BRutus.Config.CHUNK_DELAY` | 0.1 — seconds between consecutive chunks |
| `BRutus.Config.CHUNK_TIMEOUT` | 30 — seconds before discarding incomplete chunk set |
| `BRutus.Config.MSG_TYPES` | Full inventory: 11 canonical + 5 legacy types |
| `BRutus.Config.DOMAINS` | 10 sync domain name constants |
| `BRutus.Config.EVENTS` | 11 internal EventBus event names |
| `BRutus.Config.LIMITS` | Table: LOOT_HISTORY_MAX(500), STALE_PROFESSION_THRESHOLD(86400), etc. |
| `BRutus.Config.DB_SCHEMA_VERSION` | 2 — matches BRutusDB._dbVersion |

---

## Locale.lua — Localization

| Symbol | Description |
|---|---|
| `BRutus.L` | Translation table. `L["English key"]` → localized string for the active client locale, or the English key itself if untranslated (metatable `__index` returns the key). Loaded right after Config.lua. |
| `BRutus.Locale` | Active client locale string from `GetLocale()` (e.g. "enUS", "ptBR", "deDE"). |

Locale data files: `Locales/enUS.lua` (master/stub — English is implicit via metatable), `Locales/ptBR.lua`, `Locales/esES.lua` (esES+esMX), `Locales/deDE.lua`, `Locales/frFR.lua`. Each non-English file early-returns unless `GetLocale()` matches, then assigns `L["English key"] = "translation"`. Keys are the canonical English strings used directly in source.

---

## v0.4.0 — Commercial polish

| Function | Description |
|---|---|
| `BRutus.Logger.Debug/Info/Warn(msg)` | Structured logger; Debug gated by `BRutus.Logger.debug` (toggle via `/guildos debug`) |
| `BRutus:SafeCall(fn, ...)` | pcall wrapper; captures errors to `BRutus.State.errors` ring (view via `/guildos errors`) |
| `BRutus:PruneStaleData()` | Manual (`/guildos prune`) removal of cached data for members who left the guild |
| `BRutus:ShowOnboarding()` / `:MaybeShowOnboarding()` | First-run welcome wizard (once; `settings.onboarded`) |
| Slash: `/guildos minimap | debug | errors | prune` | Toggle minimap button / debug / dump errors / prune left members |

Branding: all user-facing "BRutus"/"/brutus" rebranded to "Guild OS"/"/guildos"; namespace, frame names, SavedVariables and the legacy `/brutus` alias intentionally unchanged.

---

## Core.lua — BRutus global

| Function | Description |
|---|---|
| `BRutus:Initialize()` | Bootstrap: registers addon message prefix, prints version |
| `BRutus:ResolveGuildDB()` | Resolves/creates per-guild SavedVariables DB; migrates flat structure |
| `BRutus:OnLogin()` | Handles PLAYER_LOGIN, retries guild DB resolution up to 5 times |
| `BRutus:InitModules()` | Initializes all subsystem modules in load order, respects enable flags |
| `BRutus:OnEnterWorld(isInitialLogin, isReloadingUi)` | Collects/broadcasts data on initial login or reload only |
| `BRutus:OnGuildRosterUpdate()` | Refreshes roster frame on GUILD_ROSTER_UPDATE / PLAYER_GUILD_UPDATE |
| `BRutus:HookGuildFrame()` | Replaces ToggleGuildFrame / ToggleFriendsFrame(tab 3) to open BRutus |
| `BRutus:ToggleRoster()` | Shows/hides main roster frame, creating it if needed |
| `BRutus:Print(msg)` | Gold `[BRutus]`-prefixed message to DEFAULT_CHAT_FRAME |
| `BRutus:IsOfficer()` | true if local rank index ≤ officerMaxRank setting |
| `BRutus:IsOfficerByName(fullName)` | Checks officer status by scanning guild roster |
| `BRutus:LinkAlt(altKey, mainKey)` | Links alt to main in altLinks, broadcasts (officer only) |
| `BRutus:UnlinkAlt(altKey)` | Removes alt link, broadcasts (officer only) |
| `BRutus:GetLinkedChars(playerKey)` | Returns all keys in the same alt/main account group |
| `BRutus:DeepCopy(orig)` | Recursively deep-copies a table |
| `BRutus:GetClassColor(class)` | Returns r,g,b for a WoW class token |
| `BRutus:GetClassColorHex(class)` | Returns 6-char hex string for a class color |
| `BRutus:ColorText(text, r, g, b)` | Wraps text in WoW `\|cff...` color escape |
| `BRutus:FormatItemLevel(ilvl)` | Quality-color-coded item level string |
| `BRutus:GetPlayerKey(name, realm)` | Returns "Name-Realm" composite key |
| `BRutus:TimeAgo(timestamp)` | Returns "Xm ago / Xh ago / Xd ago" string |
| `BRutus:HookChatInvite()` | Alt+Click player names → guild invite via SetItemRef hook |
| `BRutus:GetStaleProfessions()` | Returns primary professions with recipe scan age > 24h |
| `BRutus:CheckProfessionFreshness()` | Shows reminder banner if professions have stale recipe data |
| `BRutus:ShowProfessionReminder(staleProfessions)` | Creates and fades-in profession sync reminder banner |
| `BRutus:CheckAndDismissProfessionReminder()` | Fades-out reminder when all profs are fresh |
| `BRutus:DismissProfessionReminder()` | Immediately hides and clears the profession reminder banner |
| `BRutus:ShowExportPopup(titleStr, text)` | Creates copyable text export popup |
| `BRutus:GetSetting(key)` | Config accessor — reads `BRutus.db.settings[key]` (Rule 8) |
| `BRutus:SetSetting(key, value)` | Config mutator — writes `BRutus.db.settings[key]` (Rule 8) |
| `BRutus.Logger.Debug(msg)` | Structured log at DEBUG level (prints only when `BRutus.Logger.debug == true`) |
| `BRutus.Logger.Info(msg)` | Structured log at INFO level |
| `BRutus.Logger.Warn(msg)` | Structured log at WARN level (always prints) |
| `BRutus.Compat.RegisterAddonPrefix(prefix)` | Guards `C_ChatInfo.RegisterAddonMessagePrefix` (Rule 4) |
| `BRutus.Compat.GuildRoster()` | Guards `C_GuildInfo.GuildRoster()` / `GuildRoster()` fallback (Rule 4) |
| `BRutus.Compat.IsQuestComplete(questId)` | Guards `C_QuestLog.IsQuestFlaggedCompleted` / `IsQuestFlaggedCompleted` fallback (Rule 4) |
| `BRutus.Compat.After(delay, fn)` | Guards `C_Timer.After` (Rule 4) |
| `BRutus.Compat.NewTicker(interval, fn, iterations)` | Guards `C_Timer.NewTicker` (Rule 4) |
| `BRutus.Compat.NewTimer(delay, fn)` | Guards `C_Timer.NewTimer` (Rule 4) |

---

## DataCollector.lua

| Function | Description |
|---|---|
| `DataCollector:Initialize()` | Registers PLAYER_EQUIPMENT_CHANGED, SKILL_LINES_CHANGED events |
| `DataCollector:CollectMyData()` | Collects name/realm/class/level/race/gear/professions/stats/spec |
| `DataCollector:CollectGear()` | Reads GetInventoryItemLink for all BRutus.SlotIDs |
| `DataCollector:ParseItemLink(link)` | Parses enchantId and gem IDs from TBC item link |
| `DataCollector:GetEnchantName(enchantId)` | Tooltip-scans fake link to get green-text enchant name |
| `DataCollector:CalculateAvgIlvl(gear)` | Averages ilvl across all equipped gear slots |
| `DataCollector:CollectProfessions()` | Iterates GetSkillLineInfo, filters via PROF_LOOKUP |
| `DataCollector:IsProfession(name)` | Returns PROF_LOOKUP[name] ~= nil |
| `DataCollector:IsPrimaryProfession(name)` | Returns whether PROF_LOOKUP marks this as a primary profession |
| `DataCollector:GetCanonicalProfName(localizedName)` | Returns canonical English name from PROF_LOOKUP |
| `DataCollector:IsKnownProfession(name)` | Returns true if name is in PROF_LOOKUP |
| `DataCollector:IsGatheringProfession(name)` | Returns PROF_LOOKUP[name].isGathering |
| `DataCollector:CollectStats()` | Collects health/mana/STR/AGI/STA/INT/SPI via UnitStat |
| `DataCollector:StoreReceivedData(playerKey, data)` | Merges received data with timestamp check; handles recipes separately |
| `DataCollector:GetBroadcastData()` | Returns clean copy (gear/prof/attunements/spec/recipes/addonVersion) for broadcast |

---

## AttunementTracker.lua

| Function | Description |
|---|---|
| `AttunementTracker:Initialize()` | Registers QUEST_TURNED_IN event |
| `AttunementTracker:ScanAttunements()` | Scans ATTUNEMENTS quests via IsQuestFlaggedCompleted |
| `AttunementTracker:IsQuestComplete(questId)` | Checks C_QuestLog.IsQuestFlaggedCompleted with fallback |
| `AttunementTracker:GetEffectiveAttunements(playerKey)` | Returns attunements in canonical order (no alt propagation) |
| `AttunementTracker:GetAttunementSummary(playerKey)` | Returns compact color-coded "X/Y" summary string |

---

## CommSystem.lua

| Function | Description |
|---|---|
| `CommSystem:Initialize()` | Registers CHAT_MSG_ADDON, starts 5-min sync ticker |
| `CommSystem:SendMessage(msgType, data, target, priority)` | Compress, encode, chunk, send |
| `CommSystem:SendRaw(msg, target, priority)` | ChatThrottleLib:SendAddonMessage wrapper |
| `CommSystem:OnMessageReceived(msg, _, sender)` | Reassembles chunks, decompresses, routes by MSG_TYPE |
| `CommSystem:BroadcastMyData()` | Throttled (5s) broadcast of local player data |
| `CommSystem:HandleBroadcast(sender, data)` | Deserializes and stores received player data |
| `CommSystem:RequestAllData()` | Sends REQUEST "ALL" to guild |
| `CommSystem:HandleRequest(_sender, _data)` | Responds with BroadcastMyData (staggered) |
| `CommSystem:HandleResponse(sender, data)` | Delegates to HandleBroadcast |
| `CommSystem:HandlePing(sender)` | Responds with PONG + version |
| `CommSystem:HandleVersionCheck(_sender, data)` | Prints notice on version mismatch |
| `CommSystem:BroadcastAltLinks()` | Serializes and sends altLinks table (officer only) |
| `CommSystem:FullSync()` | Full staggered sync of all data types |

---

## RecruitmentSystem.lua

| Function | Description |
|---|---|
| `Recruitment:Initialize()` | Sets up DB defaults, hooks events, resumes if enabled |
| `Recruitment:CanUseRecruitment()` | Checks rank index ≤ minRankIndex or CanGuildInvite() |
| `Recruitment:StartAutoRecruit()` | Creates ticker, shows first popup after 2s |
| `Recruitment:StopAutoRecruit()` | Cancels ticker, hides popup |
| `Recruitment:Toggle()` | Toggles enabled state |
| `Recruitment:CreatePopupFrame()` | Creates click-to-send popup with glow, icon, dismiss button |
| `Recruitment:ShowSendPopup()` | Shows popup; auto-hides after 30s |
| `Recruitment:DoSendRecruitmentMessage()` | Sends to configured channels via SendChatMessage |
| `Recruitment:HookChatInvite()` | No-op (dropdown hooks removed to avoid taint) |
| `Recruitment:HandleCommand(args)` | Routes `/brutus recruit` subcommands |
| `Recruitment:RegisterWelcomeEvent()` | Initialises roster snapshot, creates CHAT_MSG_SYSTEM frame — delegates to DetectGuildJoin/HandleGuildJoin (Rule 10) |
| `Recruitment:DetectGuildJoin(msg)` | Pure pattern match: returns new member name from system message, or nil |
| `Recruitment:HandleGuildJoin(newMember)` | All welcome business logic: dedup, delay, WELCOME_CLAIM comm, SendChatMessage (Rule 10) |

---

## WishlistSystem.lua

| Function | Description |
|---|---|
| `Wishlist:Initialize()` | DB setup, data migration, rebuilds index, hooks tooltips |
| `Wishlist:RebuildItemIndex()` | Builds itemId→{wishers} index from guildWishlists |
| `Wishlist:GetItemInterest(itemId)` | Returns itemIndex[itemId] entries |
| `Wishlist:GetItemName(itemId)` | Returns GetItemInfo name or "Item #N" |
| `Wishlist:GetItemQuality(itemId)` | Returns GetItemInfo quality or 1 |
| `Wishlist:GetMyList()` | Lazily creates and returns per-character wishlist table |
| `Wishlist:AddToWishlist(itemId, itemLink, isOffspec)` | Adds/updates item, broadcasts |
| `Wishlist:IsItemDelivered(itemId)` | Checks lootHistory for ML award of item to self |
| `Wishlist:RemoveFromWishlist(itemId)` | Removes item if not delivered, reorders, broadcasts |
| `Wishlist:ReorderWishlist(itemId, direction)` | Swaps item with neighbor, broadcasts |
| `Wishlist:BroadcastMyWishlist()` | Stores locally + sends "WL" comm message |
| `Wishlist:HandleWishlistBroadcast(sender, data)` | Stores incoming wishlist into guildWishlists |
| `Wishlist:HookTooltips()` | Hooks GameTooltip/ItemRefTooltip OnTooltipSetItem |
| `Wishlist:BroadcastLootPrios()` | Serializes and sends "LP" lootPrios |
| `Wishlist:HandleLootPriosBroadcast(sender, data)` | Stores incoming prios, rebuilds index |

---

## RaidTracker.lua

| Function | Description |
|---|---|
| `RaidTracker:Is25Man(instanceID)` | Returns true if instanceID is in RAID_25MAN table |
| `RaidTracker:GetWeekNum(timestamp)` | Floor division from TBC Tuesday epoch |
| `RaidTracker:Initialize()` | DB setup, migration, registers zone/roster/encounter events |
| `RaidTracker:CheckZone()` | Manages session start/resume/end based on GetInstanceInfo |
| `RaidTracker:StartSession(instanceID)` | Creates currentRaid table, starts 5-min snapshot ticker |
| `RaidTracker:IsGuildRaid(session)` | Returns true if ≥50% players are in guild DB/roster |
| `RaidTracker:EndSession()` | Finalizes session, discards if <10min, saves |
| `RaidTracker:TakeSnapshot(reason)` | Captures raid roster with consume check into snapshots |
| `RaidTracker:CheckPlayerConsumes(unit)` | Checks flask/elixir/food buffs via ConsumableChecker |
| `RaidTracker:OnEncounterStart(encounterID, encounterName)` | Records encounter, guards duplicates |
| `RaidTracker:OnEncounterEnd(encounterID, encounterName, success)` | Updates encounter end/success |
| `RaidTracker:GetCurrentGroup()` | Returns currentGroupTag string |
| `RaidTracker:SetGroupTag(name)` | Sets group tag in memory and DB |
| `RaidTracker:GetPlayerGroup(playerKey)` | Returns group with most raids for player |
| `RaidTracker:GetAttendance(playerKey, groupTag)` | Returns attendance record for player/group |
| `RaidTracker:GetTotalSessions(groupTag)` | Counts unique guild-raid lockouts |
| `RaidTracker:GetTotal25ManSessions(groupTag)` | Counts unique 25-man lockouts |
| `RaidTracker:GetAttendancePercent(playerKey, groupTag)` | Returns overall att% using totalScore |
| `RaidTracker:GetAttendance25ManPercent(playerKey, groupTag)` | Returns 25-man att% using totalScore25 |
| `RaidTracker:GetRecentSessions(limit, only25, guildOnly)` | Returns sorted session list |
| `RaidTracker:MergeDuplicateSessions()` | Merges duplicate/nearby sessions within 30-min window |
| `RaidTracker:RebuildAttendanceFromSessions()` | Rebuilds entire attendance table from scratch |
| `RaidTracker:UpdateAttendanceForLockout(lockout)` | Computes and stores attendance for a single lockout |
| `RaidTracker:DeleteSession(sessionID)` | Deletes session, tombstones, broadcasts (officer only) |
| `RaidTracker:BroadcastDeleteSession(sessionID)` | Sends RAID_DELETE comm message |
| `RaidTracker:HandleDeleteIncoming(data)` | Applies incoming session deletion and tombstone |
| `RaidTracker:CountTable(t)` | Counts entries in a table |
| `RaidTracker:BroadcastRaidData()` | Sends compact attendance + session metadata (officer only) |
| `RaidTracker:HandleIncoming(data)` | Merges incoming raid data; handles migration, tombstones, dedup |
| `RaidTracker:ExportForTMB(groupTag)` | Exports attendance as TMB-compatible JSON string |
| `RaidTracker:MigrateAttendanceIfNeeded()` | Detects old flat attendance format and triggers rebuild |
| `RaidTracker:GetSnapshotScore(sessionData, playerKey)` | Returns score, wasLate, leftEarly, noConsumes, consumeHits, consumeChecks for a player in a session (Rule 10) |

---

## LootTracker.lua

| Function | Description |
|---|---|
| `LootTracker:Initialize()` | Ensures lootHistory DB table exists |
| `LootTracker:RecordMLAward(entry)` | Prepends entry to lootHistory, caps at 500 |
| `LootTracker:GetHistory(limit)` | Returns first N entries from lootHistory |
| `LootTracker:GetPlayerLoot(playerKey, limit)` | Filters lootHistory by player key |
| `LootTracker:GetLootCount(playerKey)` | Counts items received by player |
| `LootTracker:GetRaidLoot(raidName, limit)` | Filters lootHistory by raid name |
| `LootTracker:DeleteEntry(index)` | Removes entry at index |
| `LootTracker:ClearHistory()` | Wipes entire lootHistory |

---

## LootMaster.lua

| Function | Description |
|---|---|
| `LootMaster:SafeSendChat(msg, channel)` | Sends to raid if in raid + not testMode, else prints locally |
| `LootMaster:SafeSendAddon(prefix, payload, channel)` | Sends addon message if in raid + not testMode |
| `LootMaster:Initialize()` | DB setup, builds roll pattern, registers events |
| `LootMaster:GetPlayerContext(playerName)` | Returns {att25, recvThisLockout} for a player |
| `LootMaster:IsMasterLooter()` | 4-tier check: IsMasterLooter → GetLootMethod → C_PartyInfo → leader rank |
| `LootMaster:StartListeningForRolls()` | Sets listeningForRolls = true |
| `LootMaster:StopListeningForRolls()` | Sets listeningForRolls = false |
| `LootMaster:OnSystemMessage(message)` | Routes CHAT_MSG_SYSTEM to ProcessSystemRoll if listening |
| `LootMaster:ProcessSystemRoll(message)` | Parses /roll, validates range (1-100=MS, 1-99=OS) |
| `LootMaster:OnLootOpened()` | Collects Rare+ items if ML+in raid, shows loot frame |
| `LootMaster:OnLootClosed()` | Resets isMLSession/lootWindowOpen flags |
| `LootMaster:PlayerHasItemOnWishlist(itemId)` | Checks db.myWishlist for itemId |
| `LootMaster:ResolveWishlistCouncil(itemId)` | Returns in-raid wishlist interest sorted by order |
| `LootMaster:ResolvePrioList(itemId)` | Returns in-raid officer prio entries in order |
| `LootMaster:AnnounceItem(itemLink, lootSlot)` | Main routing: prio → council → open roll |
| `LootMaster:DoNormalAnnounce(...)` | Open MS/OS roll announce to RAID_WARNING + addon message |
| `LootMaster:AutoCouncilAward(winner, itemLink, lootSlot, allCandidates)` | Direct award for single wishlist winner |
| `LootMaster:StartRestrictedRoll(tied, ...)` | Restricted roll for tied wishlist entries |
| `LootMaster:ShowCouncilResultFrame(...)` | Council confirm popup for ML |
| `LootMaster:OnAddonMessage(...)` | Handles BRutusLM messages (ANNOUNCE, AWARD) |
| `LootMaster:RegisterRoll(name, rollType, roll)` | Validates and stores /roll result |
| `LootMaster:EndRolling()` | Stops roll capture, announces winner to raid |
| `LootMaster:AwardLoot(playerName)` | Awards via GiveMasterLoot or trade queue; records history |
| `LootMaster:QueueForTrade(playerName, itemLink, itemId)` | Queues item for trade window delivery |
| `LootMaster:FindItemInBags(itemId)` | Searches bags for itemId, returns bag/slot |
| `LootMaster:OnTradeShow()` | Auto-adds pending queued items when trade opens |
| `LootMaster:OnTradeAcceptUpdate(...)` | Marks trade complete when both sides accept |
| `LootMaster:GetPendingTrades()` | Returns pendingTrades list |
| `LootMaster:CancelRolling()` | Cancels active roll session, announces cancellation |
| `LootMaster:SendMyRoll(rollType)` | Performs RandomRoll(1-100) MS or RandomRoll(1-99) OS |
| `LootMaster:ShowRollPopup(itemLink, duration, itemId)` | Raider roll popup with MS/OS/Pass + countdown |
| `LootMaster:SetActiveLoot(link, slot, itemId)` | Sets active loot for direct award without roll |
| `LootMaster:ShowLootFrame(items)` | ML loot frame: item list + wishlist priority panel |
| `LootMaster:ShowRollFrame()` | ML roll tracker showing live rolls, prio/wishlist, attendance |
| `LootMaster:RefreshRollFrame()` | Rebuilds roll tracker content from current data |
| `LootMaster:UpdateRollTimer()` | Updates timer text on roll frame each second |
| `LootMaster:CountRolls()` | Counts active non-PASS rolls in self.rolls |
| `LootMaster:GetDisenchanter()` | Returns stored disenchanter name |
| `LootMaster:SetDisenchanter(name)` | Sets the disenchanter name |
| `LootMaster:SendToDisenchanter(itemLink, lootSlot, itemId)` | Awards to disenchanter, announces to raid |

---

## RecipeTracker.lua

| Function | Description |
|---|---|
| `RecipeTracker:Initialize()` | Registers TRADE_SKILL_SHOW/CLOSE, CRAFT_SHOW/CLOSE; enriches stored recipes; hooks tooltips |
| `RecipeTracker:EnrichStoredRecipes()` | Two-phase: name→spellId lookup, then enriches and purges ID-less entries |
| `RecipeTracker:MergeSpellIds(existing, incoming)` | Merges spellIds from existing into incoming by name matching |
| `RecipeTracker:DebounceScan(scanType)` | 5s cooldown debounce before ScanTradeSkill or ScanCraft |
| `RecipeTracker:ScanTradeSkill()` | Scans GetTradeSkillLine/GetNumTradeSkills, extracts spellId/itemId |
| `RecipeTracker:ScanCraft()` | Scans GetCraftDisplaySkillLine/GetNumCrafts (Enchanting) |
| `RecipeTracker:StoreMyRecipes(profName, recipes)` | Stores in db.recipes, cleans old locale keys, broadcasts |
| `RecipeTracker:BroadcastRecipes(profName, recipes)` | Sends "RC" CommSystem message |
| `RecipeTracker:HandleIncoming(sender, data)` | Deserializes, normalizes prof name, merges spellIds, stores |
| `RecipeTracker:GetAllProfessions()` | Returns sorted canonical profession list from db.recipes |
| `RecipeTracker:BuildRecipeIndex()` | Groups by spellId/itemId, resolves display names |
| `RecipeTracker:Search(query, profFilter)` | Searches index, marks online crafters, sorts (online first) |
| `RecipeTracker:GetOnlineSet()` | Returns set of online guild member short names |
| `RecipeTracker:BuildItemCrafterIndex()` | Builds itemId→crafters and spellId→crafters lookups |
| `RecipeTracker:HookTooltips()` | Hooks tooltips to add crafter list to item tooltips |

---

## OfficerNotes.lua

| Function | Description |
|---|---|
| `OfficerNotes:Initialize()` | Ensures officerNotes DB table exists |
| `OfficerNotes:AddNote(playerKey, text)` | Adds note entry, caps at 50, broadcasts |
| `OfficerNotes:DeleteNote(playerKey, index)` | Removes note at index (officer only) |
| `OfficerNotes:GetNotes(playerKey)` | Returns notes array or {} |
| `OfficerNotes:SetTag(playerKey, tag, value)` | Sets tag on player note record (officer only) |
| `OfficerNotes:GetTag(playerKey, tag)` | Returns specific tag value or nil |
| `OfficerNotes:GetAllTags(playerKey)` | Returns full tags table or {} |
| `OfficerNotes:BroadcastNote(playerKey, noteEntry)` | Serializes and sends "ON" comm message |
| `OfficerNotes:HandleIncoming(data)` | Deserializes, deduplicates by author+timestamp, inserts note |
| `OfficerNotes:BroadcastAllNotes()` | Serializes full officerNotes and sends "OA" comm message |
| `OfficerNotes:HandleAllIncoming(data)` | Merges incoming bulk notes, deduplicates, sorts |

---

## TrialTracker.lua

| Function | Description |
|---|---|
| `TrialTracker:Initialize()` | Ensures trials DB table; migrates old records |
| `TrialTracker:AddTrial(playerKey, sponsor)` | Creates trial entry, takes initial snapshot, broadcasts |
| `TrialTracker:UpdateStatus(playerKey, newStatus)` | Updates status, records resolvedDate/By |
| `TrialTracker:AddTrialNote(playerKey, text)` | Appends note to trial, broadcasts |
| `TrialTracker:GetTrial(playerKey)` | Returns trial data or nil |
| `TrialTracker:GetAllTrials()` | Returns all trials sorted by startDate desc |
| `TrialTracker:GetActiveTrials()` | Returns status=trial entries sorted by startDate desc |
| `TrialTracker:IsTrial(playerKey)` | Returns true if player has active trial status |
| `TrialTracker:GetDaysRemaining(playerKey)` | Returns floor of (endDate - now) / 86400 |
| `TrialTracker:GetDaysSinceStart(playerKey)` | Returns floor of (now - startDate) / 86400 |
| `TrialTracker:CheckExpired()` | Marks trials past endDate as expired, notifies officers |
| `TrialTracker:RemoveTrial(playerKey)` | Nils trial entry, broadcasts |
| `TrialTracker:TakeSnapshot(playerKey)` | Records avgIlvl, attunements, professions, level snapshot |
| `TrialTracker:GetProgress(playerKey)` | Returns delta table (ilvlDelta, attunement deltas, etc.) |
| `TrialTracker:UpdateSnapshots()` | Auto-snapshots active trials if last snapshot >1 day (officer only) |
| `TrialTracker:BroadcastTrials()` | Serializes and sends "TR" comm message (officer only) |
| `TrialTracker:HandleIncoming(data)` | Merges incoming trials: missing=accept, same=merge notes, newer=replace |
| `TrialTracker:MergeNotes(existing, incoming)` | Merges notes by author:timestamp, re-sorts |

---

## GuildManager.lua — BRutus.GuildManager (Leadership Suite)

| Function | Description |
|---|---|
| `GuildManager:Initialize()` | Ensures `db.managementLog` ring buffer exists |
| `GuildManager:CanPromote()` / `:CanDemote()` / `:CanKick()` | Nil-guarded wrappers over CanGuildPromote/Demote/Remove |
| `GuildManager:CanSetMOTD()` / `:CanSetGuildInfo()` | Nil-guarded wrappers over CanEditMOTD/CanEditGuildInfo |
| `GuildManager:GetRosterIndex(name)` | Guild roster index for a short/full name (realm-stripped match) |
| `GuildManager:GetRankIndex(name)` | Current 0-based rank index for a player name |
| `GuildManager:GetRanks()` | Ordered `{index, name}` rank list (GuildControl 1-based → 0-based) |
| `GuildManager:GetRankName(rankIndex)` | Display name for a 0-based rank index |
| `GuildManager:Promote(name)` / `:Demote(name)` / `:SetRank(name)` / `:Kick(name)` | **Protected** in Classic — route to `_protectedNotice` handoff, do NOT call the restricted API |
| `GuildManager:OpenNativeGuild()` | Opens Blizzard's native guild panel via `BRutus._origToggleGuildFrame` (handoff target) |
| `GuildManager:_protectedNotice(actionLabel, name)` | Prints "protegido pela Blizzard" notice + opens native panel; returns false |
| `GuildManager:SetMOTD(text)` / `:SetGuildInfo(text)` | Sets MOTD / Guild Info, permission-gated, logged (not protected) |
| `GuildManager:GetMOTD()` / `:GetGuildInfo()` | Reads client-cached MOTD / Guild Info text |
| `GuildManager:GetDaysOffline(rosterIndex)` | Days since last online via GetGuildRosterLastOnline (nil if online) |
| `GuildManager:GetInactiveMembers(days)` | Roster members offline ≥ days, sorted most-inactive first |
| `GuildManager:GetSuggestions()` | `{trialsReady, promoteCandidates}` from trial + attendance data |
| `GuildManager:LogAction(action, target, detail)` | Appends to capped action log (LOG_MAX 200) |
| `GuildManager:GetLog()` / `:ClearLog()` | Returns log newest-first / wipes it |
| `GuildManager:RefreshUI()` | Refreshes roster + active management sub-panel after an action |
| `GuildManager:ConfirmSetRank(name)` / `:ConfirmKick(name)` | Call-site entry points → `_protectedNotice` handoff |

---

## v0.3.0 additions — Audit / Raid Tools / QoL

| Function | Description |
|---|---|
| `AttunementTracker:GetGuildColumns()` | Raid attunements that require a quest chain (grid columns) |
| `AttunementTracker:GetGuildMatrix()` | (cols, rows) guild attunement matrix, sorted attuned-first |
| `GearAudit:GetGuildEnchantAudit()` | Rows of members with equipped-but-unenchanted slots |
| `GearAudit:GetEnchantableSlots()` | Slot IDs that should be enchanted in TBC |
| `LootTracker:GetGuildLootEquity()` | Items received vs attendance per member (dry/over-fed) |
| `RaidTracker:GetMissedStreak(key, group, cap)` | Consecutive recent 25-man guild raids missed |
| `CommSystem:GetSyncHealth()` | (rows, withAddon, outdated) addon adoption / version / last sync |
| `RaidTools:GetSource()` | (list, label) raid → party → online guild fallback |
| `RaidTools:GetClassCounts(list)` / `:ResolveCoverage(defs, counts)` | Class tally + buff/CD coverage resolution |
| `BRutus:ExportRoster()` / `:ExportLoot()` | Tab-separated exports for Sheets (English headers) |
| `BRutus:RecordFirstSeen()` / `:GetFirstSeen(key)` | "Known to GuildOS since" tracking (no join-date API) |
| `BRutus:CreateMinimapButton()` / `:ToggleMinimapButton()` | Draggable minimap button (angle/hide in settings.minimap) |
| `BRutus:CreateAuditPanel(parent)` | Audit tab: attunement grid / enchant audit / sync sub-tabs |
| `BRutus:CreateRaidToolsPanel(parent)` | Raid Tools tab: composition / cooldown coverage sub-tabs |
| `BRutus:RefreshLootEquity(content, countText)` | Loot equity sub-view of the Loot tab |

---

## ConsumableChecker.lua

| Function | Description |
|---|---|
| `ConsumableChecker:Initialize()` | Ensures consumableChecks DB table exists |
| `ConsumableChecker:CheckRaid()` | Checks all connected raid members for flask/food/elixirs |
| `ConsumableChecker:UnitHasBuff(unit, spellID, nameHint)` | Scans UnitBuff(1..40), matches by spellId or name |
| `ConsumableChecker:GetLastResults()` | Returns lastCheck.results or db.consumableChecks.lastResults |
| `ConsumableChecker:GetMissingCount(results)` | Counts players with non-empty missing array |
| `ConsumableChecker:ReportToChat(channel)` | Sends missing consumables report to raid channel |

---

## SpecChecker.lua

| Function | Description |
|---|---|
| `local CountTabPoints(tabIndex, isInspect)` | Sums GetTalentInfo currentRank for all talents in a tab |
| `local CollectTabTalents(tabIndex, isInspect)` | Returns array of {name,icon,tier,column,currentRank,maxRank} |
| `SpecChecker:CollectOwnSpec()` | Scans own talent tabs, builds spec record with full talent data |
| `SpecChecker:BuildSpecRecord(points, names)` | Finds max-point tab, returns spec record |
| `SpecChecker:GetSpecLabel(memberKey)` | Returns "41/5/15  (Protection)" string or nil |
| `SpecChecker:ScanGroup()` | Builds inspect queue from group members |
| `SpecChecker:ProcessNextInspect()` | Pops queue, calls NotifyInspect or skips if unreachable |
| `SpecChecker:OnInspectReady()` | Reads inspected unit's talents (isInspect=true), stores spec |
| `SpecChecker:Initialize()` | Registers INSPECT_READY, schedules own spec collection after 3s |

---

## UI/Helpers.lua — BRutus.UI (aliased as UI in UI files)

| Function | Description |
|---|---|
| `UI:CreatePanel(parent, name, level)` | BackdropTemplate frame with panel colors/border |
| `UI:CreateDarkPanel(parent, name, level)` | Darker sub-panel variant |
| `UI:CreateAccentLine(parent, thickness)` | Horizontal accent-colored texture strip |
| `UI:CreateSeparator(parent)` | Dim separator line texture |
| `UI:CreateTitle(parent, text, size)` | Gold FRIZQT__ FontString with shadow |
| `UI:CreateText(parent, text, size, r, g, b)` | Standard FontString |
| `UI:CreateHeaderText(parent, text, size)` | Gold 90%-opacity column header text |
| `UI:CreateButton(parent, text, width, height)` | Styled button with accent border + hover effects |
| `UI:CreateCheckbox(parent, labelText, size)` | Custom checkbox with "X" check mark and label |
| `UI:CreateCloseButton(parent)` | Red-tinted × close button with hover |
| `UI:SkinScrollBar(scrollFrame, scrollName)` | Hides default buttons, adds thin 6px accent track+thumb |
| `UI:CreateScrollFrame(parent, name)` | UIPanelScrollFrameTemplate + child + skinned scrollbar |
| `UI:CreateIcon(parent, size, iconPath)` | Bordered icon frame with inner texture |
| `UI:SetIconQuality(iconFrame, quality)` | Sets icon border color to quality color |
| `UI:CreateProgressBar(parent, width, height)` | Progress bar with frame:SetProgress(value) method |

---

## UI/RosterFrame.lua

| Function | Description |
|---|---|
| `BRutus.CreateRosterFrame()` | Creates entire main window (title bar, tabs, all panels) |
| `frame:SetActiveTab(key)` | Switches active tab, shows/hides tabPanels |
| `frame:UpdateTabVisibility()` | Repositions tabs based on officer status |
| `frame:RefreshRoster()` | BuildMemberList → UpdateSortIndicators → UpdateRows → UpdateStats |
| `frame:BuildMemberList()` | Queries GetGuildRosterInfo, merges db.members, sort/filter |
| `frame:UpdateSortIndicators()` | Sets sort arrow text on active sort column header |
| `frame:UpdateRows()` | FauxScrollFrame offset + populates VISIBLE_ROWS rows |
| `frame:UpdateStats()` | Updates member/online/addon-user counts and guild subtitle |
| `CreateRosterRow(parent, rowIndex)` | Creates a single roster row with all column text fields |
| `UpdateRosterRow(row, data, i)` | Populates row: class color, ilvl, attunements, attendance |
| `ShowRowTooltip(row)` | Shows rich hover tooltip with spec, gear, attunements, wishlist |
| `BRutus:ShowMemberContextMenu(_anchor, memberData)` | Opens right-click context menu for a member row |

---

## UI/FeaturePanels.lua

| Function | Description |
|---|---|
| `BRutus:CreateRaidsPanel(parent, _mainFrame)` | Creates Raids tab with session scroll + attendance scroll |
| `BRutus:RefreshRaidsPanel(...)` | Rebuilds grouped session list and attendance table |
| `BRutus:CreateLootPanel(parent, _mainFrame)` | Creates Loot History tab with column headers + scroll |
| `BRutus:RefreshLootPanel(content, countText)` | Rebuilds loot history rows |
| `BRutus:CreateTrialsPanel(parent, _mainFrame)` | Creates Trial Members tab |
| `BRutus:RefreshTrialsPanel(parent)` | Rebuilds trials list with expandable detail rows |
| `BRutus:CreateSettingsPanel(parent, _mainFrame)` | Creates Settings tab with scroll content area |
| `BRutus:RefreshSettingsPanel(content)` | Populates settings: module toggles, LM options, test functions |
| `BRutus:ShowWishlistFrame()` | Creates or shows personal wishlist standalone frame |
| `BRutus:RefreshWishlistFrame()` | Rebuilds wishlist FauxScroll rows |
| `BRutus:CreateRecruitmentPanel(parent, mainFrame)` | Creates Recruitment tab panel |
| `BRutus:CreateWishlistGuildPanel(parent, mainFrame)` | Creates Guild Wishlist tab panel |

---

## UI/MemberDetail.lua

| Function | Description |
|---|---|
| `BRutus:ShowMemberDetail(memberData)` | Creates (once) or reuses DetailFrame, calls PopulateDetail |
| `local CreateDetailFrame()` | Creates detail window: title bar, scroll content area |
| `local PopulateDetail(frame, data)` | Populates spec/talents/stats/gear/profs/attunements/notes/alts |
| `local CreateSectionHeader(parent, text, yOff, width)` | Gold section header with accent underline |
| `local CreateGearRow(parent, slotId, item, yOff, width)` | Gear slot row with icon, quality name, gems, enchant |
| `local CreateProfessionRow(parent, prof, yOff, width)` | Profession row with name, level, progress bar |
| `local CreateAttunementRow(parent, att, yOff, width)` | Attunement row with tier badge, status, progress bar |
| `local CreateTalentViewerFrame()` | Compact talent tree viewer with tab buttons and icon grid |
| `BRutus:ShowTalentViewer(spec, playerName, classToken)` | Opens talent tree viewer for a spec record |

---

## UI/ManagementPanel.lua

| Function | Description |
|---|---|
| `BRutus:CreateManagementPanel(parent, _mainFrame)` | Builds the "Liderança" tab: sub-tab bar + 5 sub-panels (ranks/inactive/suggest/motd/log) |
| `parent.RefreshActive()` | Re-runs the refresh of the currently visible sub-panel (called by GuildManager:RefreshUI) |
| `local BuildRanksSub(panel)` | Roster list with ▲/▼ promote/demote per row → returns refresh fn |
| `local BuildInactiveSub(panel)` | Inactivity report with day threshold + Remover (kick) per row |
| `local BuildSuggestSub(panel)` | Trials-ready (Aprovar/Negar) + promotion candidates (Promover) |
| `local BuildMotdSub(panel)` | MOTD + Guild Info editors, permission-gated |
| `local BuildLogSub(panel)` | Action log list + Limpar button |

---

## UI/RecipesPanel.lua

| Function | Description |
|---|---|
| `BRutus:CreateRecipesPanel(parent, _mainFrame)` | Searchable guild recipe browser with FauxScroll, prof filters, whisper |
| `local RefreshResults()` | Queries RecipeTracker:Search, updates state.results |
| `local CreateFilterButton(profName, anchorTo)` | Profession filter button with icon |
| `local RebuildFilterButtons()` | Hides old and recreates filter buttons |
| `local CreateRow(index)` | Single recipe row: status dot, name, prof icon, crafters, whisper |
| `panel:UpdateRows()` | Updates VISIBLE_ROWS from FauxScroll offset + state.results |

---

## UI/RaidHUD.lua

| Function | Description |
|---|---|
| `BRutus:CreateRaidHUD()` | Floating raid CD tracker frame |
| `BRutus:UpdateRaidHUDVisibility()` | Shows/hides HUD based on module flag + IsInRaid + IsLeaderOrAssist |
| `BRutus:ShowConsumablePopup()` | Creates or shows consumable check popup |
| `local FormatTime(s)` | Formats seconds as "Xm Ys" or "Xs" |
| `local IsLeaderOrAssist()` | Returns true if raid leader or officer rank ≥ 1 |
| `local ScanRaidRoster()` | Wipes and rebuilds _raidMembers from GetRaidRosterInfo |
| `local UpdateRow(row)` | Updates a HUD CD row's player text with remaining cooldowns |
| `local BuildHUDRows(f)` | Rebuilds all CD rows from current raid roster |
| `local BuildConsPopup(f)` | Builds consumable grid rows in popup frame |
