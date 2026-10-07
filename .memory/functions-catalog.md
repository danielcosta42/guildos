# GuildOS — Complete Function Catalog

## Config.lua — GuildOS.Config (NEW — Phase 1)

| Symbol | Description |
|---|---|
| `GuildOS.Config.ADDON_NAME` | "GuildOS" |
| `GuildOS.Config.VERSION` | mirrors GuildOS.VERSION ("1.0.0") |
| `GuildOS.Config.COMM_VERSION` | mirrors GuildOS.COMM_VERSION (1) |
| `GuildOS.Config.PREFIX` | mirrors GuildOS.PREFIX ("GuildOS") |
| `GuildOS.Config.CHUNK_SIZE` | 230 — max bytes per addon message chunk |
| `GuildOS.Config.BROADCAST_THROTTLE` | 5 — min seconds between broadcasts |
| `GuildOS.Config.SYNC_TICKER_INTERVAL` | 300 — periodic sync interval (s) |
| `GuildOS.Config.INIT_REQUEST_DELAY` | 8 — seconds before requesting guild data |
| `GuildOS.Config.CHUNK_DELAY` | 0.1 — seconds between consecutive chunks |
| `GuildOS.Config.CHUNK_TIMEOUT` | 30 — seconds before discarding incomplete chunk set |
| `GuildOS.Config.MSG_TYPES` | Full inventory: 11 canonical + 5 legacy types |
| `GuildOS.Config.DOMAINS` | 10 sync domain name constants |
| `GuildOS.Config.EVENTS` | 11 internal EventBus event names |
| `GuildOS.Config.LIMITS` | Table: LOOT_HISTORY_MAX(500), STALE_PROFESSION_THRESHOLD(86400), etc. |
| `GuildOS.Config.DB_SCHEMA_VERSION` | 2 — matches GuildOSDB._dbVersion |

---

## Locale.lua — Localization

| Symbol | Description |
|---|---|
| `GuildOS.L` | Translation table. `L["English key"]` → localized string for the active client locale, or the English key itself if untranslated (metatable `__index` returns the key). Loaded right after Config.lua. |
| `GuildOS.Locale` | Active client locale string from `GetLocale()` (e.g. "enUS", "ptBR", "deDE"). |

Locale data files: `Locales/enUS.lua` (master/stub — English is implicit via metatable), `Locales/ptBR.lua`, `Locales/esES.lua` (esES+esMX), `Locales/deDE.lua`, `Locales/frFR.lua`. Each non-English file early-returns unless `GetLocale()` matches, then assigns `L["English key"] = "translation"`. Keys are the canonical English strings used directly in source.

---

## v0.4.0 — Commercial polish

| Function | Description |
|---|---|
| `GuildOS.Logger.Debug/Info/Warn(msg)` | Structured logger; Debug gated by `GuildOS.Logger.debug` (toggle via `/guildos debug`) |
| `GuildOS:SafeCall(fn, ...)` | pcall wrapper; captures errors to `GuildOS.State.errors` ring (view via `/guildos errors`) |
| `GuildOS:PruneStaleData()` | Manual (`/guildos prune`) removal of cached data for members who left the guild |
| `GuildOS:ShowOnboarding()` / `:MaybeShowOnboarding()` | First-run welcome wizard (once; `settings.onboarded`) |
| Slash: `/guildos minimap | debug | errors | prune` | Toggle minimap button / debug / dump errors / prune left members |

Branding: user-facing text says "Guild OS" and the commands are `/guildos` and `/gos`; the old name, its global alias, saved variable, comm prefix and slash commands are gone (#120).

---

## v0.54 — Forever skin (#13)

| Symbol | Description |
|---|---|
| `GuildOS.Colors.<token>` | Handoff tokens: `bg`, `panel`, `popup`, `well`, `line`, `lineHi`, `text`, `textSoft`, `label`, `labelDim`, `disabled`, `gold`, `onGold`, `ok`, `danger`, `info`, `epic`. Legacy keys (`silver`, `accent`, `border`…) are copies of the token that plays their role (ADR-0013) |
| `GuildOS.Fonts` | Files `serif`, `serifStrong`, `mono`, `monoStrong`; roles `wordmark`, `windowTitle`, `sectionTitle`, `body`, `memberName`, `itemName`, `caption`, `tableNum`, `colHeader`, `metricValue`, `countdown`, `badge` as `{ file, size }`; `normal`/`number` alias `mono` |
| `GuildOS:ChipLabel(text, maxBytes)` | A removable chip's label: the text cut to `maxBytes` (14) on a character boundary (`SanitizeUserText`), `..` only when something was cut, then `  x` (issue #59) |
| `UI:SetChipText(btn, text, width)` | Sets a chip's label from `ChipLabel`, shortening it until it fits `width` in the font drawing it, and keeps the chip at `width` (issue #59) |
| `GuildOS:ApplyFont(fontString, size, role)` | Sets a font: a role wins, else Spectral from 14px and IBM Plex Mono below (clamped to 10px); never outlined; falls back to `STANDARD_TEXT_FONT` only when `SetFont` returns false. With `GuildOSDB.font == "game"` (account-wide, Settings > General, issue #57) every text uses `STANDARD_TEXT_FONT` at the same size |
| `GuildOS.UI:SetButtonVariant(btn, variant)` | Switches a `CreateButton` button to `"primary"` (gold fill, `glow-gold.tga`), `"secondary"` (default), `"ghost"` (underlined label) or `"danger"`; returns the button |
| `GuildOS.UI:CreateMetricChip(parent, value, caption, size)` | Metric chip: mono value, 1px gold rule (34px), `labelDim` caption; `chip:SetValue(text)` |
| `GuildOS.UI:_ButtonState(btn, state)` | Internal: paints `"rest"`, `"hover"`, `"pressed"` or `"disabled"` for the button's variant, in the same frame |

Removed: `GuildOS.ACCENT_PRESETS`, `GuildOS:ApplyTheme()`.

---

## v0.55 — One window (#14)

| Symbol | Description |
|---|---|
| `UI:OpenWindow(id, sub, filter)` | The one opener: refuses an unknown id or a background module, then says disabled / could not start / officer-only; shows the window, unfolds it when the saved fold says so, opens tab `id` (remembered), then `panel.SelectSub(sub, filter)`; true when the tab opened (ADR-0016) |
| `UI:ToggleMain()` | Shows or hides the window on the remembered tab |
| `UI:GetMainWindow()` | The window (`GuildOS.RosterFrame`, frame `GuildOSWindow`), created on first use; nil before the saved data loads |
| `UI:ApplyScale()` / `UI:OnFeatureToggled()` | Pushes `uiScale` onto the window / re-checks its tabs after a Settings toggle |
| `UI:ClampWindowRect(left, top, w, h, sw, sh)` | Pure: a saved rectangle pulled onto a screen of sw × sh, between 320×28 and the screen's size |
| `UI:SaveWindowGeometry(frame)` / `UI:RestoreWindowGeometry(frame)` | `settings.window.left/top/w/h`; restore clamps, or 1000×620 centred (capped to the scaled screen) when nothing is saved |
| `window:SetActiveTab(key, byUser)` | Opens a tab, building its panel the first time (one that raised stays refused); `byUser` remembers it |
| `window:UpdateTabVisibility()` | Re-checks every tab with `UI:IsFeatureAllowed`; falls back to Now when the open tab is gone |
| `window:LayoutTabs(width)` | Places the tabs that fit (`UI:FitTabs`) and folds the rest into "»n", or shows the selector in the watch band |
| `window:LayoutFooter(width)` | Footer actions by priority through `UI:ResolveColumns`; the invite field only for who can invite |
| `window:Layout(width)` | Applies the band, measured on the content area (the width less its padding): title bar height, padding, rule or selector, the switch to Now and back, the bar |
| `window:ToggleCollapsed()` / `window:Settle()` | Folds to or restores from the 28px bar / after the grip, folds into or out of the bar band |
| `window:RefreshTitle()` | Guarded: guild and online count (a dash while the roster loads), sync time, and the bar's three numbers only in the bar band |
| `UI.LADDER` / `UI.LADDER_HYSTERESIS` / `UI:ResolveBand(width, current)` | The handoff §6 bands (full, wide, medium, compact, narrow, watch, bar) and the band for a width, which moves only 16px past a line |
| `UI:FitTabs(widths, available, gap, moreW, active)` | Pure: the tab indices that fit beside "»n" and how many fold; the active tab always stays |
| `UI:CreateTab(parent, text, width, sub)` / `UI:StyleSubTabBar(bar)` | `sub = true` draws the 1px sub-tab rule / puts a sub-tab bar on `panel`; a tab grows to its label like a button (issue #28) |
| `UI.Agora:NextRaid()` / `Agora.Clock(dt)` / `Agora.Short(dt)` | The next future RAID (or kindless) calendar event; "4:12:38" or "2d 4h"; "4h12" |
| `UI.Agora:NeedsMe()` | `{ text, urgent, id, sub, filter }` items, urgent first, only for screens the player can open; an unanswered raid carries its time as the calendar's filter |
| `UI.Agora:Activity(limit)` | The last 48 hours, newest first, at most 12: roster log (with the member when exactly one saved member has that name), loot (with the member), milestones, raids tracked (at their end); `{ ts, text, id, sub, key }` |
| `UI.Agora:OnlineCount()` / `RosterLoading()` / `LastSync()` / `BarText()` | Members online; in a guild with the roster not in yet; newest member sync; "online · time to raid · pending", with dashes for the counts while the roster loads |
| `GuildOS:CreateNowPanel(panel, win)` | Builds Now: the live column, and the home cards beside it from 780px. Fetches on show, every tenth tick of its 1s clock and on roster updates; a resize only repaints |
| `panel.SelectSub(key, filter)` / `subPanel.ApplyFilter(value)` | Deep links: every panel with sub-tabs exposes `SelectSub`; the Guild tab hands `filter` to a sub-panel's `ApplyFilter`, and the calendar's selects the day of a timestamp |

Removed: `UI.Hub`, `UI:CreateWindow`, `UI:ToggleWindow`, `UI:IsWindowOpen`, `UI:GetWindow`, `UI:CloseAllWindows`, `UI:RaiseWindow`, `GuildOS:ToggleExpanded`, `GuildOS.CreateRosterFrame`; the registry's `hub`, `w`, `h`, `minW`, `minH`, `resizable` and `icon`.

---

## v0.56 — Member keys without a realm (#8)

| Symbol | Description |
|---|---|
| `GuildOS:GetClientRealm()` | The client's realm for keys: `GetRealmName()`, else `GetNormalizedRealmName()`, else nil ("" counts as nothing) |
| `GuildOS:GetPlayerKey(name, realm)` | The one member-key rule: an empty realm counts as absent and the client's fills it; with a realm "Name-Realm", without one the name alone (ADR-0018). On WoW: Forever the passed realm is ignored and the client's always used, since a guild's clients answer different realm names (issue #95) |
| `GuildOS:RekeyMembersToThisRealm()` | Forever only, at `DataCollector:Initialize`: moves `db.members` records keyed with another client's realm to this client's key; the newer `lastUpdate` wins (a tie keeps the one already there) and the older one's fields fill the winner's gaps (issue #95) |
| `PugInspector:Classify(name, srcs)` | Builds its table key with `GetPlayerKey` when the name or the sources give a realm, else the bare name (issue #95) |
| `GuildOS:LocalMemberKey(key)` | A member key another client built, as this client keys it: on Forever rebuilt from its name with this client's realm (`ally:` keys left alone); elsewhere unchanged (issue #97) |
| `GuildOS:LocalizeMemberTable(t, merge)` | `t` rekeyed with `LocalMemberKey`; `merge(held, incoming)` settles two records for one member and only sees two tables; a record beats a non-record, and with no merge the first record stays (issue #97) |
| `GuildOS:LocalizeStoredMemberTables()` | Forever only, at `DataCollector:Initialize`, once per database (`db.storedKeysLocalized` holds the realm it ran for), each table its own `SafeCall` step: rekeys stored attendance (not the old flat format), sessions' players and snapshots, officer notes, trials, raiders, alt links (a self-link dropped), DKP standings (summed, starting points once) and core rosters and sign-ups (issue #97) |

Every hand-built member key now goes through the rule: CommSystem's own-message check, `/gos trial` and `/gos note`,
RaidTracker snapshots, the consumable check, the export's `guildKey`, LootMaster's context, awards, rolls and DKP
charge, the wishlist and received broadcasts. `tools/member-keys.lua` scans the TOC's files, so a new `.. "-" ..`
join, `"%s-%s"` format or literal realm fallback fails the test.

---

## v0.57 — Compat core loop (#10)

| Symbol | Description |
|---|---|
| `Compat.GetItemInfo(item)` | `C_Item.GetItemInfo`, else `GetItemInfo`; every return passed through; nothing when neither exists |
| `Compat.GetSpellInfo(spell)` / `Compat.GetSpellTexture(spell)` | `C_Spell` (its table mapped to the global's order: name, rank, icon, castTime, minRange, maxRange, spellID), else the globals |
| `Compat.UnitBuff(unit, index)` | `C_UnitAuras.GetBuffDataByIndex` mapped to `UnitBuff`'s order (spellId tenth), else `UnitBuff` |
| `Compat.GetContainerNumSlots` / `GetContainerItemLink` / `GetContainerItemInfo` / `UseContainerItem` | `C_Container`, else the old globals; 0 slots with neither; item info is always the namespaced table |
| `Compat.GetNumTalentTabs(isInspect)` / `GetNumTalents` / `GetTalentInfo` | The talent globals; the counts return `nil, "no-api"` when the client has none |
| `Compat.InviteUnit(name)` | Group invite: `C_PartyInfo.InviteUnit`, else `InviteUnit`, else `InviteByName`; nothing on a client with none (issue #43) |
| `Compat.GetItemQualityColor(quality)` / `Compat.GetItemCount(item, includeBank)` | `C_Item`'s, else the old global's; white / 0 with neither (issue #43) |
| `Compat.PopupEditBox(dialog)` | A StaticPopup's edit box: `GetEditBox()` / `EditBox` on WoW: Forever, `editBox` on Anniversary (issue #49) |
| `Compat.TraitTreeNodes()` | WoW: Forever's talent tree: `{ {x = posX, points = ranksPurchased}, ... }` for the active config; `nil, "no-api"` with no trait API, `nil, "no-config"` before talents load (issue #41) |
| `Compat.GetNumSkillLines()` / `GetSkillLineInfo(i)` | The skill-line globals; the count returns `nil, "no-api"` when the client has none |
| `Compat.SendAddonMessage(prefix, text, channel, target, prio, queueName)` | Through ChatThrottleLib (BULK by default), acting on the result: a lockdown holds it and every later send until combat ends, the zone changes or a 2-second poll finds it lifted (200 at most, oldest dropped); a channel throttle retries after 1, 2, 4 and 8 s; any other failure, or a message the client would refuse (prefix over 16 bytes, text over 255, no channel, unknown priority), is recorded once per reason and dropped (ADR-0019) |
| `Compat.SendAddonMessageNow(prefix, text, channel, target)` | Sent at once past ChatThrottleLib's queue with the same results, and an AddonMessageThrottle (which ChatThrottleLib would have re-queued) retried after 1, 2, 4 and 8 s: loot messages, whose roll timers start at send |
| `Compat.FlushHeldMessages()` | Sends what a lockdown held, in order and one at a time under pcall (one that raises is recorded, the rest still go); while it lasts, each is held again |
| `Compat.ChannelHidesRaidIcons(name, number)` | Does the server show this channel without raid icons (ChatChannels DisableRaidIcons → the chat event's `suppressRaidIcons`)? On WoW: Forever General 1, Trade 2, LocalDefense 22, Services 42, TradeLocal 46, by zone channel id from `C_ChatInfo.GetChannelInfoFromIdentifier` (name, else the number as a string, as Blizzard's own UI looks it up); on Anniversary no channel (issue #64) |
| `Compat.SetWhoToUI(toApi)` / `Compat.WhoExact(name)` | `/who` on both clients: `C_FriendList.SetWhoToUi` (lower-case i, its real name everywhere) first; `WhoExact` builds each client's own exact filter: `WHO_TAG_EXACT .. C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(name)` on Forever, `WHO_TAG_EXACT .. name` on Anniversary, else `n-"Name"`. Giving the flag back leaves it on while Blizzard's Who list is open (issue #71) |
| `Compat.NeedsClick()` | True on WoW: Forever, where the game drops a chat line, a guild invite or a `/who` an addon starts from a timer or an event; such actions wait for a click there (issue #61) |
| `Compat.PlayerName()` | My own name as the roster and addon-message senders write it: on a client with surnames (`GuildOS.Client.has.surnames`, WoW: Forever) `UnitFullName("player")`'s first name and surname joined with a space, else `UnitName("player")`; a missing, empty or secret surname falls back too. Every own-name read goes through it (issue #26) |
| `Compat.IsPlayer(unit)` | Whether a group unit is me by `UnitIsUnit(unit, "player")`, never by name; a secret comparison is false (issue #26) |
| `DataCollector:CollectProfessions()` | nil without a skill-line API, so `professions` is left out of the record, the broadcast and the export |
| `SpecChecker:CollectOwnSpec()` | `nil, "no-api"` without any talent API (neither tabs nor trait trees): the saved spec is removed and no re-collect is waited for. On Forever it reads the trait tree instead (issue #41) |
| `DataCollector:CollectMyData()` / `GetBroadcastData()` / `StoreReceivedData(key, data)` | A field left out because its API is missing is named in `absent`; the broadcast carries it, and a receiver drops the `spec` or `professions` it held for that member |
| `tools/compat-guard.lua` | CI lint step: exits 1 naming each file:line that reaches a version-sensitive API outside `Core/Compat.lua` (a call, an existence check, a concatenation, `_G.Name`, a quoted string index on a plain name on the same line, a namespace, ChatThrottleLib or `_G` alias, a single-name `Compat` alias, `getfenv`, a sender on anything but Compat), or a TOC file missing on disk (Probe and ChehulNet exempt); it reads names, not expressions |

Removed: `Compat.NewTimer`.

---

## Core.lua — GuildOS global

| Function | Description |
|---|---|
| `GuildOS:Initialize()` | Bootstrap: registers addon message prefix, prints version |
| `GuildOS:ResolveGuildDB()` | Resolves/creates per-guild SavedVariables DB; migrates flat structure |
| `GuildOS:OnLogin()` | Handles PLAYER_LOGIN, retries guild DB resolution up to 5 times |
| `GuildOS:InitModules()` | Starts every module from the `MODULE_START` list (then `OFFICER_START` once the guild rank is known, asked every 5s up to a minute, after which it gives up as the `OfficerModules` start-up problem, counted in the login line and listed in `/guildos errors`; issue #79), each isolated; respects enable flags |
| `GuildOS:StartModule(entry)` | Starts one start-list entry (`{ name, feature, ui, method, after }`); skipped (not failed) when not loaded or switched off |
| `GuildOS:RunStartup(name, entry, fn, ...)` | xpcall one start-up step; on failure records `State.startup.failed[name]` (stack in `State.startup.stacks[name]`), marks `entry.feature` / `entry.ui` as failed, and hands the error to `geterrorhandler()` in debug mode |
| `GuildOS:ListStartupProblems()` | Sorted lines for every start-up failure and missing capability; `/guildos errors` prints them before the capped error ring |
| `GuildOS:FeatureStartFailed(id)` | Module name whose failed start-up took feature `id` down, or nil; the window refuses to open |
| `GuildOS:RecordMissing(what)` | Records, once per session, an event or tooltip script this client lacks (`State.missing`) |
| `GuildOS:ReportStartup()` | One localized chat line when start-up had failures or misses; silent otherwise |
| `GuildOS:RecordError(msg)` | Pushes a message into the `/guildos errors` ring (shared by SafeCall and start-up) |
| `GuildOS:OnEnterWorld(isInitialLogin, isReloadingUi)` | Collects/broadcasts data on initial login or reload only |
| `GuildOS:OnGuildRosterUpdate()` | Refreshes roster frame on GUILD_ROSTER_UPDATE / PLAYER_GUILD_UPDATE |
| `GuildOS:HookGuildFrame()` | `hooksecurefunc` on ToggleGuildFrame (never replaced: replacing taints the social frame). After Blizzard's toggle: its frame came up and Guild OS is closed → hide it (HideUIPanel) and open Guild OS; came up while Guild OS is open → hide it and close Guild OS (the key's second press, issue #66); went down → close Guild OS too. `_suppressGuildHijack` (OpenBlizzardGuildUI) skips it |
| `GuildOS:ToggleRoster()` | Opens or closes the Guild OS window (`UI:ToggleMain`); guildless, opens the recruitment finder instead |
| `GuildOS:IsFrontDoorShown()` / `GuildOS:HideFrontDoor()` | Whether the window is on screen / closes it; the guild-frame hook mirrors Blizzard's open and close onto them |
| `GuildOS:RefreshRosterUI()` | Refreshes the roster when the window is shown and the roster tab has been built |
| `GuildOS:Print(msg)` | Gold `[GuildOS]`-prefixed message to DEFAULT_CHAT_FRAME |
| `GuildOS:IsOfficer()` | true if local rank index ≤ officerMaxRank setting |
| `GuildOS:IsOfficerByName(fullName)` | Checks officer status by scanning guild roster |
| `GuildOS:SetOfficerMaxRank(n)` / `PublishOfficerMaxRank(justChanged)` / `OnOfficerMaxRankSync(env)` | The guild's officer threshold (issue #81): an officer's change is stamped (`settings.officerMaxRankAt`) and published on the `guildcfg` SyncService officer domain; officers re-send it on the 5-minute sync and when asked; a local change is stamped past the one held and goes out even when it demotes the sender; every client keeps the newest stamp (a real time, held to 5 min ahead of its clock; a tie goes to the lower threshold), a whole rank 0..9, sent by an officer over GUILD. `SetOfficerMaxRank` returns false and does nothing for a non-officer. A threshold set before #81 that is not the default is shared by the Settings button |
| `GuildOS:LinkAlt(altKey, mainKey)` | Links alt to main in altLinks, broadcasts (officer only) |
| `GuildOS:UnlinkAlt(altKey)` | Removes alt link, broadcasts (officer only) |
| `GuildOS:GetLinkedChars(playerKey)` | Returns all keys in the same alt/main account group |
| `GuildOS:DeepCopy(orig)` | Recursively deep-copies a table |
| `GuildOS:GetClassColor(class)` | Returns r,g,b for a WoW class token |
| `GuildOS:GetClassColorHex(class)` | Returns 6-char hex string for a class color |
| `GuildOS:ColorText(text, r, g, b)` | Wraps text in WoW `\|cff...` color escape |
| `GuildOS:FormatItemLevel(ilvl)` | Quality-color-coded item level string |
| `GuildOS:GetPlayerKey(name, realm)` | "Name-Realm", byte for byte as in 0.53.0; the name alone when neither the caller nor `GuildOS:GetClientRealm()` has a realm (nil or ""); nil for no name (ADR-0018) |
| `GuildOS:RosterKey(name)` | The roster frame's key for somebody on the roster (roster name, its realm or the player's), the shown name and the roster's whole name; nil when nobody has that name (issue #49) |
| `GuildOS:SplitNameAndText(rest)` | `<name> <text>` from a slash command: a Forever two-word name when it is exactly somebody's roster name, else the first word; nil when the whole text is exactly a roster name, with or without realm (issue #49) |
| `GuildOS:TimeAgo(timestamp)` | Returns "Xm ago / Xh ago / Xd ago" string |
| `GuildOS:HookChatInvite()` | Alt+Click player names → guild invite via SetItemRef hook |
| `GuildOS:GetStaleProfessions()` | Returns primary professions with recipe scan age > 24h |
| `GuildOS:CheckProfessionFreshness()` | Shows reminder banner if professions have stale recipe data |
| `GuildOS:ShowProfessionReminder(staleProfessions)` | Creates and fades-in profession sync reminder banner |
| `GuildOS:CheckAndDismissProfessionReminder()` | Fades-out reminder when all profs are fresh |
| `GuildOS:DismissProfessionReminder()` | Immediately hides and clears the profession reminder banner |
| `GuildOS:ShowExportPopup(titleStr, text)` | Creates copyable text export popup |
| `GuildOS:GetSetting(key)` | Config accessor — reads `GuildOS.db.settings[key]` (Rule 8) |
| `GuildOS:SetSetting(key, value)` | Config mutator — writes `GuildOS.db.settings[key]` (Rule 8) |
| `GuildOS:ShowsItemTooltipInfo(tooltip)` | Gate for the guild lines on item tooltips (crafters, wishlist, soft res): setting `itemTooltip` = `"always"` / `"shift"` / `"off"`; a clicked chat link (`ItemRefTooltip`) passes in shift mode |
| `GuildOS.Logger.Debug(msg)` | Structured log at DEBUG level (prints only when `GuildOS.Logger.debug == true`) |
| `GuildOS.Logger.Info(msg)` | Structured log at INFO level |
| `GuildOS.Logger.Warn(msg)` | Structured log at WARN level (always prints) |
| `GuildOS.Compat.RegisterAddonPrefix(prefix)` | `C_ChatInfo.RegisterAddonMessagePrefix`, else the legacy `RegisterAddonMessagePrefix` (Rule 4, #10) |
| `GuildOS.Compat.GuildRoster()` | Guards `C_GuildInfo.GuildRoster()` / `GuildRoster()` fallback (Rule 4) |
| `GuildOS.Compat.IsQuestComplete(questId)` | Guards `C_QuestLog.IsQuestFlaggedCompleted` / `IsQuestFlaggedCompleted` fallback (Rule 4) |
| `GuildOS.Compat.After(delay, fn)` | Guards `C_Timer.After` (Rule 4) |
| `GuildOS.Compat.NewTicker(interval, fn, iterations)` | Guards `C_Timer.NewTicker` (Rule 4) |
| `GuildOS.Compat.RegisterEvent(frame, event, expected)` | `RegisterEvent` that tolerates an event the client does not know; records the miss (`GuildOS:RecordMissing`) and returns false. `expected` marks an event only some clients ever had: recorded, but not a start-up problem (ADR-0012, ADR-0020) |
| `GuildOS.Compat.HookTooltip(tooltip, script, fn)` | `HookScript` where the tooltip has `script`, else one `TooltipDataProcessor.AddTooltipPostCall` per script and function, answering only for the tooltips that asked and never for a forbidden one; `fn(tooltip, data)` on both. Nil tooltip skipped silently, a client with neither path recorded (ADR-0012, ADR-0020) |
| `GuildOS.Compat.TooltipItem(tooltip)` / `TooltipSpell` / `TooltipUnit` | What the tooltip is showing: the frame's own `GetItem`/`GetSpell`/`GetUnit` first, then `TooltipUtil.GetDisplayed*`. Name and link, name and spell id, name and unit; the retail client adds a third return (ADR-0020) |
| `GuildOS.Compat.FindGuildRosterIndex(name, realm)` | Roster index for `Name` or `Name-Realm` (an exact `Name-Realm` wins; a short name only when unique), or nil and why: `"absent"` or `"ambiguous"` |
| `GuildOS.Compat.GetGuildPublicNote(name, realm)` | The member's public note, or nil and the same reason |
| `GuildOS.Compat.SetGuildPublicNote(name, text, realm)` | Writes a sanitized, 31-byte public note through `C_GuildInfo.SetNote(guid, note, true)`, falling back to `GuildRosterSetPublicNote(index, note)`; returns true, or false and why: `"no-permission"`, `"absent"`, `"ambiguous"`, `"no-guid"`, `"no-api"` (#5) |
| `GuildOS.NoteCommand:_Refused(sender, why)` | Tells the officer whose client tried a `!note` write why it did not happen (absent, ambiguous, no GUID, no API, permission lost before the write). The chat hook tells the member who typed a `!note` their character cannot apply, on their own client only |
| `GuildOS.Client` | Which client this is, read once at load: `version`, `build`, `date`, `interface`, `projectId` (diagnostics only), `isAnniversary` (TBC Classic project id and interface 20500–29999 together), `maxLevel` (the game's level cap: 70, or 60 on WoW: Forever; every "top level" check reads it, issue #53), `raidSizes` / `defaultRaidSize` (10/25/40 and 25, or 10/20/40 and 20 on Forever; the calendar's sizes and every size default, issues #89, #92) and `has.secrets` / `chatLockdown` / `tradeSkillUI` / `tooltipData` / `guildSetNote` (ADR-0014) |
| `GuildOS.Probe:Run()` | `/guildos probe`: records the build, project id, `GuildOS.Client`, game mode, the Secret Values APIs and whether they are enforced (`C_Secrets.HasSecretRestrictions`), chat lockdown and instance type, the first roster name, `GetNormalizedRealmName()` and `GetRealmName()`, one GUILD addon message on the `GuildOSProbe` prefix, and present or missing for every inventory API, template, tooltip script and event, into `GuildOSDB.probe` (overwritten each run). Refuses in combat; never raises (ADR-0015) |
| `GuildOS.Probe.APIS` / `TEMPLATES` / `SCRIPTS` / `EVENTS` | The inventory the probe checks; `tools/probe.lua` fails when the source registers an event missing from `EVENTS` |
| `GuildOS.Probe:PrintSummary(result)` | One-screen chat summary of a probe result |
| `GuildOS.Probe:RunChat()` / `FinishChat()` | `/guildos probe chat` (issue #75): two GUILD lines, one from the command (a key press) and one from a 1s timer; each is `echoed` when `CHAT_MSG_GUILD` brings it back (a secret echo sets `unreadable`). Six seconds later `needsClick` is measured (`true`, `false`, or `"unknown"` when the command's line did not come back, the timer's never went out, or its echo may have been unreadable) and printed next to `Compat.NeedsClick()`, with every block seen, into `GuildOSDB.probeChat`, with the full build (`version.build`) and the active `Enum.AddOnRestrictionType` names (or `"missing"`) at the start and as each line went. A timer's line never goes after the verdict; the verdict prints at most five blocks. Refuses in combat, outside a guild and while running |
| Probe's blocked-action frame | `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` (any addon) and `MACRO_ACTION_BLOCKED` / `FORBIDDEN` (addon `macro`): `RecordError("<event>: <addon> tried <function>")` for `/guildos errors`, once per event, addon and function a session, and every one into the running chat probe; secret names read as `?` (issue #75) |

---

## DataCollector.lua

| Function | Description |
|---|---|
| `DataCollector:Initialize()` | Registers PLAYER_EQUIPMENT_CHANGED, SKILL_LINES_CHANGED events |
| `DataCollector:CollectMyData()` | Collects name/realm/class/level/race/gear/professions/stats/spec |
| `DataCollector:CollectGear()` | Reads GetInventoryItemLink for all GuildOS.SlotIDs |
| `DataCollector:ParseItemLink(link)` | Parses enchantId and gem IDs from TBC item link |
| `DataCollector:GetEnchantName(enchantId)` | Tooltip-scans fake link to get green-text enchant name |
| `DataCollector:CalculateAvgIlvl(gear)` | Averages ilvl across all equipped gear slots |
| `DataCollector:CollectProfessions()` | Iterates GetSkillLineInfo, filters via PROF_LOOKUP |
| `DataCollector:IsProfession(name)` | Returns PROF_LOOKUP[name] ~= nil |
| `DataCollector:IsPrimaryProfession(name)` | Returns whether PROF_LOOKUP marks this as a primary profession |
| `DataCollector:GetCanonicalProfName(localizedName)` | Returns canonical English name from PROF_LOOKUP. That is what is stored and synced; every screen shows it as `L[name]` (issue #114), and `tools/locales.lua` counts each RegisterProf name, so a profession without a translation fails CI |
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
| `CommSystem:SendRaw(msg, target, priority)` | Sends one sync message through `Compat.SendAddonMessage`: guild at BULK or the given priority, whisper at NORMAL (ADR-0019) |
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
| `Recruitment:Initialize()` | Officer stage: first drops a member popup ticker started while the rank was unknown (issue #79), then sets up DB defaults, hooks events, resumes if enabled |
| `Recruitment:CanUseRecruitment()` | Checks rank index ≤ minRankIndex or CanGuildInvite() |
| `Recruitment:StartAutoRecruit()` | Creates ticker, shows first popup after 2s; refuses with the Recruitment module off (issue #84) |
| `Recruitment:_OfficerTick()` | One officer popup; with the module switched off it shows nothing and keeps the ticker, so the next tick after the module is back shows one (issue #84) |
| `Recruitment:StopAutoRecruit()` | Cancels ticker, hides popup |
| `Recruitment:Toggle()` | Toggles enabled state |
| `Recruitment:CreatePopupFrame()` | Creates click-to-send popup with glow, icon, dismiss button |
| `Recruitment:ShowSendPopup()` | Shows popup; auto-hides after 30s |
| `Recruitment:DoSendRecruitmentMessage()` | Sends to configured channels via SendChatMessage |
| `Recruitment:HookChatInvite()` | No-op (dropdown hooks removed to avoid taint) |
| `Recruitment:HandleCommand(args)` | Routes `/gos recruit` subcommands; with no `db.recruitment` (a member whose officers never started recruitment) it says so instead of raising (issue #59) |
| `Recruitment:SetAutoInviteKeyword(cfg, word)` / `SetAutoInviteMinLevel(cfg, n)` / `SetAutoInviteClass(cfg, class, on)` / `SetAutoInviteFallback(cfg, mode)` | The auto-invite settings' one door, for `/gos autoinvite` and Recruitment > Recruiting: a keyword is one lowercase word (≤ 20), a level 0..`Client.maxLevel`, a class only one in `CLASSES` (`IsClass`; `_DropUnknownClasses` clears typos the old command stored, at `Initialize`), the fallback `skip`/`invite`. Return what they stored, or nil/false (issue #59) |
| `Recruitment:_StripRaidIcons(msg)` | The recruitment post's copy for a channel where `Compat.ChannelHidesRaidIcons` drops `{rt1}`..`{rt8}` and `ICON_TAG_LIST` words (a code between words leaves a space); a channel left empty is skipped, and if that leaves nothing posted it says so (issue #64) |
| `Recruitment:QueueWelcome(name)` / `SendPendingWelcome()` / `DismissPendingWelcome()` | WoW: Forever (`Compat.NeedsClick`): the welcome waits in `ShowWelcomePopup` and the officer's click sends one line for everyone waiting (issue #61) |
| `Recruitment:QueueInvite(name, full)` / `InviteNext()` / `SkipNext()` | WoW: Forever: a keyword whisper's invite waits in `ShowInvitePopup`, keeping the whisper's own name (`full`, what an Alt-click's link invites with). Invite acts on the one shown only: banned since queued → dropped with a note, on cooldown → dropped, else `_InviteNow(name, full)`. Skip marks the cooldown. No `/who` filter there (issue #61) |
| `RecruitScanner:WhisperSelected(names)` / `WhisperNext()` / `PendingWhispers()` | On Forever the batch's first whisper goes out in the confirm click and the rest wait in `_whisperQueue`, one per click on "Whisper next"; a name goes on cooldown when it is actually whispered; `Scan()` drops an unfinished batch. Anniversary keeps the 1.5s timed whispers (issue #61) |
| `Recruitment:AddChannel(list, name)` / `RemoveChannel(list, name)` | Recruitment channels, listed once whatever the case; used by `/gos recruit channel` and the Channels row (issue #59) |
| `Recruitment:PresetChannels()` / `ChannelName(name)` / `HasChannel(list, name)` | Trade, LookingForGroup and GuildRecruitment (Anniversary only) as this client names them, from the game's ChatChannels table per language (`Recruitment.CHANNELS`; Forever esES LFG is BuscarGrupo). `ChannelName` turns a preset named in any language into this client's name, at post time, so an English default or an officer's channels from another language still post; Add/Remove/Has compare through it, and a channel saved in two languages is posted to once (issue #112). LookingForGroup goes by its name, zone channels by their shortcut (they differ only on Forever ruRU); on Forever GuildRecruitment is not a preset |
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
| `RaidTracker:Is25Man(instanceID, size)` / `IsTracked(instanceID)` / `ProgLabel(text)` | Whether a night counts for progression: by id on Anniversary (`RAID_25MAN`), by the session's `size` (20 and up) on WoW: Forever; whether a raid is tracked (RAID_INSTANCES on Anniversary, every raid on Forever); a "25-man" label as the game says it ("20+" on Forever) (ADR-0024, issue #90) |
| `RaidTracker:SetGroupTag(name)` | Sets group tag in memory and DB, and re-reads the loot rules (`LootMaster:LoadCfg`) (issue #99) |
| `RaidTracker:DetectCore(group, reason)` | After each snapshot inside the raid, until settled: the core whose roster covers `group` (`CoreManager:CoreForGroup`) becomes the active core and the session's, named in chat when it first appears or changes; `encounter_start` settles it; never in the grace period or on `session_end` (ADR-0023, issue #99) |
| `RaidTracker:PickCore(name)` | An officer's pick (CorePanel's Set Active): sets the active core. Inside a raid it also moves the session, settles detection and is kept in `db.raidTracker.corePick` for that character and instance while the raid goes on (refreshed by each snapshot, lapsing 30 min after the last; cleared by `EndSession`), so a /reload keeps it; on a run-back it waits in `gracePick` for the raid to resume; outside any raid it drops a kept pick (ADR-0023, issue #99) |
| `RaidTracker:SayPicked()` | Names in chat a core pick applied with no click right then: a pick kept across a /reload, or one made on the run-back (issue #99) |
| `CoreManager:CoreForGroup(players)` | The core with the most of a group on its roster (alts as their main), if at least 2 and at least half the group and untied; returns name, count, size; nil otherwise (ADR-0023, issue #99) |
| `RaidTracker:GetPlayerGroup(playerKey)` | Returns group with most raids for player |
| `RaidTracker:GetAttendance(playerKey, groupTag)` | Returns attendance record for player/group |
| `RaidTracker:GetTotalSessions(groupTag)` | Counts unique guild-raid lockouts |
| `RaidTracker:GetTotal25ManSessions(groupTag)` | Counts unique 25-man lockouts |
| `RaidTracker:GetAttendancePercent(playerKey, groupTag)` | Returns overall att% using totalScore |
| `RaidTracker:GetAttendance25ManPercent(playerKey, groupTag)` | Returns 25-man att% using totalScore25 |
| `RaidTracker:GetRecentSessions(limit, only25, guildOnly)` | Returns sorted session list |
| `RaidTracker:MergeDuplicateSessions()` | Merges duplicate/nearby sessions within 30-min window |
| `RaidTracker:RebuildAttendanceFromSessions()` | Rebuilds entire attendance table from scratch |
| `RaidTracker:GetPenalties(groupTag)` | The late / left-early / no-consumables weights a raid of that group is scored with: `CoreManager:GetPenalties` (the core's own, else the guild's in `db.attendancePenalties` — raids outside a core and cores that set none — else 10). Every score and every screen reads it; `RaidTracker.PENALTIES` is only the defaults (issue #55) |
| `CoreManager:RaidSizes()` / `NextRaidSize(size)` / `RaidTargets(size)` / `GetRaidSize(core)` / `SetRaidSize(core, size)` | The raid formats a core plans for, per game: 10 and 25 on Anniversary (default 25), 10, 20 and 40 on WoW: Forever (default 20); a saved size the game lacks reads as the default; `RaidTargets` is the T/H/M/R composition, which sums to the size (issue #89). The default comes from `GuildOS.Client.defaultRaidSize`, which the calendar uses too, with `GuildOS.Client.raidSizes` (10/25/40 or 10/20/40). On Forever, `CLASS_DEFAULT_ROLE` puts every class on damage first and `GetComposition` lists no raid buffs, as the site's Forever catalogue (issue #92) |
| `CoreManager.CLASS_ROLES` / `RolesFor(class)` / `RoleFor(class, role)` | The roles each class can play, the same in both games (the site's lists); `RolesFor` in tank/healer/melee/ranged order; `RoleFor` keeps a role the class can play, else the class's own (`CLASS_DEFAULT_ROLE`). The sign-up window offers `RolesFor` (no buttons for a one-role class), `BroadcastSignup(core, note, role)` sends the pick, and the officer storing a sign-up takes the class the guild roster gives (`GetMemberRecord`, the server's), else a known payload class, else warrior, and runs the role through `RoleFor`. `/gos signup <core> [tank|healer|melee|ranged] [note]` takes a role word too (`ROLE_WORDS`); the window keeps a typed note across a role click (issue #94) |
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
| `LootMaster:SafeSendChatAuto(msg, channel)` | A line sent from an event or a timer: on WoW: Forever (`Compat.NeedsClick`) it prints for the loot master only, else `SafeSendChat`. Used by `RegisterRoll`'s per-roll lines and the timer path of `EndRolling(byClick)`; `ScheduleCountdownWarnings` does nothing on Forever (issue #63) |
| `LootMaster:SafeSendAddon(prefix, payload, channel)` | Sends addon message if in raid + not testMode |
| `LootMaster:Initialize()` | DB setup, builds roll pattern, registers events |
| `LootMaster:LoadCfg()` | Caches the active core's roll timer, auto-announce, wishlist-only mode, disenchanter and threshold; run at start-up and whenever the active core changes (issue #99) |
| `LootMaster:GetPlayerContext(playerName)` | Returns {att25, recvThisLockout} for a player |
| `LootMaster:IsMasterLooter()` | 4-tier check: IsMasterLooter → GetLootMethod → C_PartyInfo → leader rank |
| `LootMaster:HookBagClicks()` | Alt+click on a bag item → roll: hooks `ContainerFrameItemButton_OnModifiedClick` (Anniversary) or `HandleModifiedItemClick` with the item location (Forever), never both (issue #44) |
| `LootMaster:RollFromBagClick(bagId, slotId)` | The click's checks (module on, Alt, master looter), then `RollFromBag` |
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
| `LootMaster:OnAddonMessage(...)` | Handles GuildOSLM messages (ANNOUNCE, AWARD) |
| `LootMaster:RegisterRoll(name, rollType, roll)` | Validates and stores /roll result |
| `LootMaster:EndRolling(byClick)` | Stops roll capture and announces the winner to raid. `byClick` is the End Rolling button; the roll timer ends it without, and on WoW: Forever that winner line only prints for the loot master (issue #63) |
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
| `OfficerNotes:MergeSheet(existing, incoming)` | Folds one member's sheet into another: every held note kept, an arriving one added unless the same author+timestamp is held, newest first, non-notes dropped; incoming non-empty tags win (issue #97) |

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
| `TrialTracker:Merge(existing, incoming)` | The trial to keep: latest activity (start, last note, resolution) wins, a tie merges notes and keeps more snapshots; used on receipt and by the stored-key migration (issue #97) |
| `TrialTracker:MergeNotes(existing, incoming)` | Merges notes by author:timestamp, re-sorts |

---

## GuildManager.lua — GuildOS.GuildManager (Leadership Suite)

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
| `GuildManager:OpenNativeGuild()` | Opens Blizzard's native guild panel through `GuildOS:OpenBlizzardGuildUI` (Blizzard's toggle with the hijack suppressed); false when that is missing (handoff target) |
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
| `RaidTools:GetClassCounts(list)` / `:ResolveCoverage(defs, counts)` | Class tally + buff/CD coverage resolution; definitions with `tbc = true` are skipped outside TBC Anniversary (ADR-0014) |
| `GuildOS:ExportRoster()` / `:ExportLoot()` | Tab-separated exports for Sheets (English headers) |
| `GuildOS:RecordFirstSeen()` / `:GetFirstSeen(key)` | "Known to GuildOS since" tracking (no join-date API) |
| `GuildOS:CreateMinimapButton()` / `:ToggleMinimapButton()` | Draggable minimap button (angle/hide in settings.minimap) |
| `GuildOS:CreateAuditPanel(parent)` | Audit tab: attunement grid / enchant audit / sync sub-tabs |
| `GuildOS:CreateRaidToolsPanel(parent)` | Raid Tools tab: composition / cooldown coverage sub-tabs |
| `GuildOS:RefreshLootEquity(content, countText)` | Loot equity sub-view of the Loot tab |

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
| `SpecChecker:CollectOwnTraitSpec()` | WoW: Forever: points per classic tree from the trait tree; `nil, "no-points"` / `"no-config"` / `"no-trees"` while there is nothing to read; the collector does not hold the snapshot open for them, the periodic collect picks the spec up |
| `SpecChecker.ColumnPoints(nodes)` | Pure: splits `{x, points}` nodes into the three classic trees (gap > 1200 starts a tree; the three biggest groups are the trees, a stray node counts for the nearest) and returns their points left to right, or nil |
| `SpecChecker:GetSpecLabel(memberKey)` | Returns "41/5/15  (Protection)" string or nil |
| `SpecChecker:ScanGroup()` | Builds inspect queue from group members |
| `SpecChecker:ProcessNextInspect()` | Pops queue, calls NotifyInspect or skips if unreachable |
| `SpecChecker:OnInspectReady()` | Reads inspected unit's talents (isInspect=true), stores spec |
| `SpecChecker:Initialize()` | Registers INSPECT_READY, schedules own spec collection after 3s |

---

## UI/Helpers.lua — GuildOS.UI (aliased as UI in UI files)

| Function | Description |
|---|---|
| `UI:CreatePanel(parent, name, level)` | Window surface: `bg` fill with a 1px `line` border |
| `UI:CreateDarkPanel(parent, name, level)` | Darker sub-panel variant |
| `UI:CreateAccentLine(parent, thickness)` | Horizontal accent-colored texture strip |
| `UI:CreateSeparator(parent)` | Dim separator line texture |
| `UI:CreateTitle(parent, text, size)` | Window title: Spectral 16 in `text` (paper), no outline or shadow |
| `UI:CreateText(parent, text, size, r, g, b)` | Body or table text, font by size through `ApplyFont` (mono below 14px); paper unless a colour is given |
| `UI:CreateHeaderText(parent, text, size)` | Column header: IBM Plex Mono Medium 10 (`colHeader`) in `label` |
| `UI:CreateButton(parent, text, width, height)` | Button, secondary by default (1px `line` border, paper label); 26px unless a height is given; see `SetButtonVariant`. A label that spills past it (inside 2px margins) grows it to the label + 16px, at creation and on every later `btn.label:SetText`; a label that fits leaves the width alone, and it never shrinks (issue #28) |
| `UI:CreateCheckbox(parent, labelText, size)` | 14px `well` box, 1px border, solid 8px gold mark; `checkbox.onChanged(cb, checked)` |
| `UI:CreateCloseButton(parent)` | × in `label`; paper on a `popup` square with a `lineHi` border when hovered |
| `UI:SkinScrollBar(scrollFrame, scrollName)` | Hides the default buttons; 8px `well` track, `lineHi` thumb (`label` on hover) |
| `UI:CreateScrollFrame(parent, name)` | UIPanelScrollFrameTemplate + child + skinned scrollbar |
| `UI:CreateIcon(parent, size, iconPath)` | Bordered icon frame with inner texture |
| `UI:SetIconQuality(iconFrame, quality)` | Sets icon border color to quality color |
| `UI:CreateProgressBar(parent, width, height, ramp)` | Progress bar with frame:SetProgress(value) method. Gold while in progress, ok when complete; `ramp = true` for scores that can be bad (ok ≥80%, gold ≥60%, danger below) |

---

## UI/RosterFrame.lua

| Function | Description |
|---|---|
| `frame:RefreshRoster()` | BuildMemberList → UpdateSortIndicators → UpdateRows → UpdateStats |
| `frame:BuildMemberList()` | Queries GetGuildRosterInfo, merges db.members, sort/filter |
| `frame:UpdateSortIndicators()` | Sets sort arrow text on active sort column header |
| `frame:UpdateRows()` | FauxScrollFrame offset + populates VISIBLE_ROWS rows |
| `frame:UpdateStats()` | Updates member/online/addon-user counts |
| `CreateRosterRow(parent, rowIndex)` | Creates a single roster row with all column text fields |
| `UpdateRosterRow(row, data, i)` | Populates row: class color, ilvl, attunements, attendance |
| `ShowRowTooltip(row)` | Shows rich hover tooltip with spec, gear, attunements, wishlist |
| `GuildOS:ShowMemberContextMenu(_anchor, memberData)` | Opens right-click context menu for a member row |

---

## UI/FeaturePanels.lua

| Function | Description |
|---|---|
| `GuildOS:CreateRaidsPanel(parent, _mainFrame)` | Creates Raids tab with session scroll + attendance scroll |
| `GuildOS:RefreshRaidsPanel(...)` | Rebuilds grouped session list and attendance table |
| `GuildOS:CreateLootPanel(parent, _mainFrame)` | Creates Loot History tab with column headers + scroll |
| `GuildOS:RefreshLootPanel(content, countText)` | Rebuilds loot history rows |
| `GuildOS:CreateTrialsPanel(parent, _mainFrame)` | Creates Trial Members tab |
| `GuildOS:RefreshTrialsPanel(parent)` | Rebuilds trials list with expandable detail rows |
| `GuildOS:CreateSettingsPanel(parent, _mainFrame)` | Creates Settings tab with scroll content area |
| `GuildOS:RefreshSettingsPanel(content)` | Populates settings: module toggles, LM options, test functions |
| `GuildOS:ShowWishlistFrame()` | Creates or shows personal wishlist standalone frame |
| `GuildOS:RefreshWishlistFrame()` | Rebuilds wishlist FauxScroll rows |
| `GuildOS:CreateRecruitmentPanel(parent, mainFrame)` | Creates Recruitment tab panel |
| `GuildOS:CreateWishlistGuildPanel(parent, mainFrame)` | Creates Guild Wishlist tab panel |

---

## UI/MemberDetail.lua

| Function | Description |
|---|---|
| `GuildOS:ShowMemberDetail(memberData)` | Creates (once) or reuses DetailFrame, calls PopulateDetail |
| `local CreateDetailFrame()` | Creates detail window: title bar, scroll content area |
| `local PopulateDetail(frame, data)` | Populates spec/talents/stats/gear/profs/attunements/notes/alts |
| `local CreateSectionHeader(parent, text, yOff, width)` | Gold section header with accent underline |
| `local CreateGearRow(parent, slotId, item, yOff, width)` | Gear slot row with icon, quality name, gems, enchant |
| `local CreateProfessionRow(parent, prof, yOff, width)` | Profession row with name, level, progress bar |
| `local CreateAttunementRow(parent, att, yOff, width)` | Attunement row with tier badge, status, progress bar |
| `local CreateTalentViewerFrame()` | Compact talent tree viewer with tab buttons and icon grid |
| `GuildOS:ShowTalentViewer(spec, playerName, classToken)` | Opens talent tree viewer for a spec record |

---

## UI/ManagementPanel.lua

| Function | Description |
|---|---|
| `GuildOS:CreateManagementPanel(parent, _mainFrame)` | Builds the "Liderança" tab: sub-tab bar + 5 sub-panels (ranks/inactive/suggest/motd/log) |
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
| `GuildOS:CreateRecipesPanel(parent, _mainFrame)` | Searchable guild recipe browser with FauxScroll, prof filters, whisper |
| `local RefreshResults()` | Queries RecipeTracker:Search, updates state.results |
| `local CreateFilterButton(profName, anchorTo)` | Profession filter button with icon |
| `local RebuildFilterButtons()` | Hides old and recreates filter buttons |
| `local CreateRow(index)` | Single recipe row: status dot, name, prof icon, crafters, whisper |
| `panel:UpdateRows()` | Updates VISIBLE_ROWS from FauxScroll offset + state.results |

---

## UI/RaidHUD.lua

| Function | Description |
|---|---|
| `GuildOS:CreateRaidHUD()` | Floating raid CD tracker frame |
| `GuildOS:UpdateRaidHUDVisibility()` | Shows/hides HUD based on module flag + TBC Anniversary (`GuildOS.Client.isAnniversary`) + IsInRaid + IsLeaderOrAssist |
| `GuildOS:ShowConsumablePopup()` | Creates or shows consumable check popup |
| `local FormatTime(s)` | Formats seconds as "Xm Ys" or "Xs" |
| `local IsLeaderOrAssist()` | Returns true if raid leader or officer rank ≥ 1 |
| `local ScanRaidRoster()` | Wipes and rebuilds _raidMembers from GetRaidRosterInfo |
| `local UpdateRow(row)` | Updates a HUD CD row's player text with remaining cooldowns |
| `local BuildHUDRows(f)` | Rebuilds all CD rows from current raid roster |
| `local BuildConsPopup(f)` | Builds consumable grid rows in popup frame |

---

## v0.57 — Professions on WoW: Forever (#31)

Forever only: `Data/ProfCatalogForever.lua`, `Modules/Professions.lua` and `Modules/ProfSync.lua` return at
once on Anniversary. See ADR-0022 and `docs/superpowers/specs/2026-09-27-professions-foundation-design.md`.

| Symbol | Description |
|---|---|
| `Compat.GetProfessions()` | Spell-book indices of the player's professions (two primaries, First Aid, Fishing, Cooking…), nils included |
| `Compat.GetProfessionInfo(i)` | `name, icon, rank, maxRank, numSpells, spellOffset, skillLine, …` for a `GetProfessions` index |
| `Compat.IsPlayerSpell(id)` | Boolean; on Forever it answers for a recipe with the window closed |
| `Compat.TradeSkillLearned()` | `line, { learned recipeIDs }` of the open window — only the player's own, settled view |
| `Compat.RecipeLine(recipeID)` | The parent skill line of a recipe (`GetTradeSkillLineForRecipe`'s third return) |
| `Compat.GuildMemberProfessions()` | `{ { name, lines = { skillLine… } } }` from the Communities roster, addon or not; secret fields skip the member |
| `Compat.GuildChatStreams()` | The guild club's channels this player can read, `{ { id, name, kind } }` with kind `guild`, `officer` or `other` (General and Discord left out); nil without a guild club, `nil, "locked"` in a chat lockdown (#126) |
| `Compat.GuildChatHistory(max, streamId)` | The last `max` lines of a channel (nil = /g), oldest first, as `{ t, n, c, m }`; deleted and secret messages left out; nil without a guild club, `nil, "locked"` in a lockdown |
| `Compat.WatchGuildChat(on, streamId)` | `FocusStream` / `UnfocusStream`; works in a lockdown, /g by its remembered id |
| `Compat.RequestOlderGuildChat(count, streamId)` | Older lines before the newest range's oldest, or the recent ones (`nil` id) when nothing is held; nothing in a lockdown |
| `Compat.SendGuildStream(streamId, text)` | `C_Club.SendMessage` to a channel the guild made; false when it is no longer listed |
| `Compat.IsGuildClub(clubId)` | True when a club event is the guild's club; false for a secret id |
| `Compat.InChatLockdown()` | Forever's chat lockdown; false on a client without one |
| `GuildChat:Streams()` / `:Entries(stream)` / `:Watch(on, stream)` / `:Send(text, stream)` | The Chat tab's model (#124, #126): channels, lines (server first, the /g log as fallback, nil in a lockdown), focus counted across feeds, sending to /g, /o or a made channel |
| `GuildOS:CreateGuildChatFeed(parent, opts)` | The chat feed (`UI/CommunityPanel.lua`): Guild > Chat with `{ streams = true }`, the Now card with /g alone; returns its refresh |
| `GuildOS.ProfCatalog` | Generated by `tools/prof_catalog.py <build>`: `build`, `F` (field indices), `professions[line] = { child, primary, en }`, `specs[spellID] = line`, `stations[focusID] = name`, `byLine[line] = { recipeIDs }`, `recipes[recipeID] = { line, yellow, grey, out, outCount, enchant, reqSkill, spec, focus, src, recipeItem, category, reagents }` |
| `Professions.OwnKey()` | The player's member key |
| `Professions.IdList(t, cap)` | Sorted, de-duplicated copy of a list of positive integer IDs, or nil (not IDs, or past `cap`) |
| `Professions.Hash(recipes, extra)` | Adler-32 of the sorted IDs; what a summary announces and a list must match |
| `Professions:Scan()` | Reads the player's lines (`GetProfessionInfo`), specialization and recipes (`IsPlayerSpell` over `byLine`); true when the record changed, then schedules a summary |
| `Professions:ReadWindow()` | The own window's learned recipes the catalog lacks become the line's `extra` |
| `Professions:ReadNative()` | At most once a minute: members without an addon record get the roster's profession lines, no rank |
| `Professions:Get(key)` / `:KnowsRecipe(key, id)` / `:CraftersOf(id)` / `:Members(line)` | Queries on `db.professions`; `CraftersOf` uses a cached inverted index rebuilt on change |
| `Professions:OwnSummary()` / `:OwnLine(line)` | What `ProfSync` sends |
| `Professions:ApplySummary(key, p)` | A guildmate's summary (validated, capped); returns the lines whose list it still needs, nil when malformed |
| `Professions:ApplyList(key, line, h, recipes, extra)` | Stores a list only if it hashes to `h` and `h` is the latest summary's, and it is not held yet |
| `Professions.KeyFor(name)` | Member key for a roster name or a sender, by the roster's rule: the name's suffix, else the client's realm |
| `Professions:AddLearned(recipeID)` | `NEW_RECIPE_LEARNED`: a recipe the catalog lacks goes to its line's extra, then a scan |
| `Professions:LegacyList(key)` | `{ name = en, rank, maxRank, isPrimary }` for a member (no rank if native), or nil; the roster and `GetMemberRecord` fall back to it |
| `Professions:Project(key)` | Legacy adapter: `db.recipes[key][en]` (`{ name, itemId, spellId }`) only — it never creates a `db.members` row; a pending list shows the previous one |
| `Professions:OwnLegacyList()` | The player's own list for `DataCollector:CollectProfessions`; scans first if needed, never nil |
| `ProfSync:PublishSummary()` / `:ScheduleSummary(delay)` | `sum` on GUILD; after 10s of quiet following a change (a later change pushes it back), every 600s, and on `ask` |
| `ProfSync:SenderKey(sender)` | Member key of a sender in the guild roster, from the sender only; nil otherwise |
| `ProfSync:OnEnvelope(env, sender)` | `sum` → apply + `req` (re-asked after 120s); `ask` → own summary; `req` → aggregated 3s; `list` → `ApplyList` |
| `ProfSync:FlushLine(line)` | One `list`: whisper for one requester, GUILD for several |
| `tools/prof_catalog.py` | No args: self-test on `tools/prof-catalog-fixture/`; `<build> [--cache dir]`: writes the catalog from wago.tools DB2 |
| `tools/professions.lua` | Harness: Compat, collection, native, sync, integration points, the real catalog, Anniversary |

---

## v0.58 — Profession directory on WoW: Forever (#33)

Forever only (`Modules/ProfDirectory.lua`, `UI/ProfessionsPanel.lua` return at once on Anniversary). Reads only.

| Symbol | Description |
|---|---|
| `ProfDirectory.Lines()` | Catalog profession lines: primaries, then secondaries, each by localized name |
| `ProfDirectory.DisplayName(line)` | `L[en]` for a line (pt-BR names in `Locales/ptBR.lua`) |
| `ProfDirectory.RecipeName(id)` | Localized recipe name via `Compat.GetSpellInfo`, cached once resolved; `"#id"` until then |
| `ProfDirectory.Coverage(line)` | `{ total, covered, crafters }` |
| `ProfDirectory.RecipeRows(line, mode, query)` | Catalog recipes (every line when nil, each once) filtered by `mode` (`all`/`guild`/`gaps`) and a plain, case-insensitive query; sorted by yellow rank, then name |
| `ProfDirectory.MemberRows(line)` | `{ key, name, class, online, rank, max, spec, count, native }`, ranked first, native last |
| `ProfDirectory.Roster()` | `key -> { name, class, online }` from the guild roster, read once per call |
| `ProfDirectory.ItemRecipes(itemID)` | Catalog recipes creating an item (map built once per catalog) |
| `ProfDirectory.CraftersForItem(itemID)` / `CraftersForSpell(spellID)` | RecipeTracker's `{ { playerName, playerKey, class, profName } }` or nil; `RecipeTracker:GetCraftersFor*` route here on Forever |
| `ProfDirectory.Reagents(id)` | `{ { itemID, count } }` |
| `GuildOS:CreateProfessionsPanel(parent, win)` | The Professions tab on Forever: profession rail with coverage, Recipes / Crafters views, search, All / In the guild / Nobody crafts filters, recipe card with reagents, source, requirements and whisper buttons |
| `tools/professions-panel.lua` | Builds the panel under a permissive frame stub and drives it like a user |

## v0.58 — Professions in the companion export (#35)

| Symbol | Description |
|---|---|
| `CompanionExport` payload v7 | Each member row carries `crafting` on WoW: Forever (`craftingFor(key)`): `[{ line, rank, max, spec?, recipes }]` for an addon record, `[{ line, native = true }]` for a guild-roster-only one; absent without a profession model or a record |

## v0.59 — The look, read in the barber's chair (#37)

Forever only (`Modules/Look.lua` returns at once on Anniversary).

| Symbol | Description |
|---|---|
| `Look.Read()` | The barber's chair's current choices as `{ {optionID, choiceID}, ... }`, one per option, by option, at most 32; nil outside the chair |
| `Look:Keep(look)` | Keeps a look on the player's own `db.members[key].look` (and `db.myData`), prints one line and forces a broadcast, once per change |
| `Look:Initialize()` | Keeps `Look.Read()` a frame after `BARBER_SHOP_OPEN`; hooks `C_BarberShop.ApplyCustomizationChoices` to read what is being bought and keeps it on `BARBER_SHOP_APPEARANCE_APPLIED` (the game stands the player up before that event) |
| `DataCollector:GetBroadcastData()` | Carries `look`; receivers keep it through the generic merge |
| `CompanionExport` payload v8 | Each member row carries `look` when the record has a list |
| `tools/look.lua` | Drives the module through a stubbed chair: read, keep, quiet repeat, a preview is not kept, a purchase kept after the chair is gone, no erase, cap, Anniversary |

## RecruitEngagement.lua

| Function | Purpose |
|---|---|
| `RecruitEngagement:GetAggregate(now)` | Rows and totals for the engagement screen: the reports received over GUILD, with the viewer's own built locally by `_OwnPacket` (CommSystem drops one's own messages, so the echo never carried it; issue #51). Shown, never stored |
| `RecruitEngagement:BroadcastStats()` | Sends `_OwnPacket` over GUILD (`RECRUIT_STATS`), answering a REQUEST |

## CallToArms.lua — GuildOS.CallToArms (issue #108)

| Function | Description |
|---|---|
| `CTA:Templates()` / `Template(id)` | The five ready-made kinds (worldboss, pvp, defend, event, rally) then the officer's own (`db.cta.templates`, cap 12) |
| `CTA:SaveTemplate(name, text, kind)` / `DeleteTemplate(id)` | An officer's own template; name and text sanitized (no escape codes), kind falls back to rally |
| `CTA:Send(templateId, text)` | Officers only, one call per 60s (`db.cta.lastSent`, survives /reload): publishes `cta`/`call` with kind, title, text ({zone} filled with the caller's zone), zone and map position; posts a guild chat line first unless `ctaChat` is off (pcall; needs the click or slash behind it on Forever) and the call carries `chat = true` when it went; the caller gets the popup too (#110) unless their popups are off or `Quiet()` holds, and it counts for the 10s popup gap |
| `CTA:OnSync(env, sender)` | `call`: dedupe by id, drop calls older than 10 min or stamped over 5 min ahead and a second call from one sender inside 30s, sanitize every field, map position kept only inside 0-100, unknown kind = rally, then `Alert`. `going`: counts the sender once, and a repeat repaints nothing |
| `CTA:Alert(e)` | Muted kind: nothing. Popups off, quiet in an instance/combat (`ctaQuiet`), or another popup inside 10s: a chat line, skipped when the caller's own guild line went (`chat`). Else the popup |
| `CTA:ShowPopup(e)` / `Answer(id)` | One popup at a time (newest wins, hides after 30s, sound unless `ctaSound` is off); "On my way" publishes `cta`/`going` once, and is hidden on the caller's own call |

`cta` is in `SyncService.OFFICER_DOMAINS` (only an officer over GUILD may call); `going` is in `MEMBER_ACTIONS.cta` — member actions are keyed by domain and taken only over GUILD, or a member's `guildcfg` dressed as an RSVP made them an officer. The Guild hub's "Call to Arms" sub-tab (`BuildCallToArmsSub`) sends, lists recent calls with their own "On my way", and holds each player's settings; its rows flow and wrap (`flow`), and it repaints only while visible; `/gos cta [type] [message]` sends or opens it.
