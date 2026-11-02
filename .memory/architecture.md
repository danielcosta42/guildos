# GuildOS — Architecture

_Last updated: 2026-04-26_

---

## Design Principles

1. **Single global namespace** — `GuildOS` only. All sub-modules are nested tables.
2. **Separation of concerns** — each file owns exactly one responsibility.
3. **Defensive coding** — every API call that may not exist is guarded via `GuildOS.Compat`.
4. **Classic-first compatibility** — no API is called outside `GuildOS.Compat` if it may vary by version.
5. **No UI in the data pipeline** — data modules have zero UI dependencies.
6. **One-way data flow** — `Game Events → Modules → State/DB → UI reads`.

---

## Target Folder Structure

```
GuildOS/
  GuildOS.toc              — load order, SavedVariables declaration
  Core.lua                — GuildOS global, DB defaults, events, slash cmds, utilities,
                            Logger, Compat, State, Config (GetSetting/SetSetting)
  Libs/                   — LibStub, CallbackHandler, LibSerialize, LibDeflate, ChatThrottleLib
  DataCollector.lua       — player data collection (gear, professions, stats, spec)
  AttunementTracker.lua   — quest-based attunement detection
  CommSystem.lua          — guild addon message protocol (send/receive/chunk/route)
  RecruitmentSystem.lua   — auto-recruit messages + welcome detection
  WishlistSystem.lua      — per-character wishlists + loot prios
  RaidTracker.lua         — raid session tracking, attendance, score
  LootTracker.lua         — loot history recording
  LootMaster.lua          — ML loot distribution UI and logic
  RecipeTracker.lua       — profession recipe scanning
  OfficerNotes.lua        — officer note management + sync
  TrialTracker.lua        — trial member lifecycle
  GuildManager.lua        — leadership suite: ranks/kick/MOTD/inactivity/suggestions/log
  GearAudit.lua           — guild-wide enchant audit (from synced gear)
  RaidTools.lua           — composition / buff & cooldown coverage
  Locales/
    Locale.lua            — GuildOS.L bootstrap (metatable fallback to English key)
    enUS.lua              — master/stub (English is implicit)
    ptBR.lua esES.lua deDE.lua frFR.lua ruRU.lua koKR.lua zhCN.lua zhTW.lua itIT.lua — translations
                          (guarded by GetLocale; itIT is retail's alone, #186)
  ConsumableChecker.lua   — flask/elixir/food buff detection
  SpecChecker.lua         — spec/talent detection
  UI/
    Helpers.lua           — ALL UI factory + theme (current; target: split below)
    RosterFrame.lua       — main guild roster window + tabs
    MemberDetail.lua      — per-member detail slide-in panel
    ManagementPanel.lua   — "Liderança" tab (rank/inactivity/suggestions/MOTD/log)
    AuditPanel.lua        — "Audit" tab (attunement grid / enchant audit / sync health)
    RaidToolsPanel.lua    — "Raid Tools" tab (composition / cooldown coverage)
    Minimap.lua           — draggable minimap button (no LibDBIcon)
    FeaturePanels.lua     — raids, loot, trials, settings, wishlist, recruitment panels
    RecipesPanel.lua      — profession recipes panel
    RaidHUD.lua           — floating CD tracker + consumable check popup
```

### Target UI split (next refactor step)

The current `UI/Helpers.lua` mixes three distinct responsibilities. The target is to split it:

```
UI/
  Theme.lua       ← C table (colors, sizes, score helpers) — no frames
  Core.lua        ← component factory: CreateButton, CreateText, CreateHeaderText,
                    CreateCloseButton, SkinScrollBar, _ApplyBackdrop, backdrop probe
  Helpers.lua     ← (thin shim) delegates to Theme + Core for backward compat
  Panels.lua      ← compound panel builders: CreateRosterTabs, panel headers, etc.
  RosterFrame.lua ← main roster window (uses Theme + Core)
  MemberDetail.lua
  FeaturePanels.lua
  RecipesPanel.lua
  RaidHUD.lua
```

Until that split is done, all UI code continues to use `GuildOS.UI` / the `UI` local alias.

---

## Module Map

| File | Responsibility | Does NOT own |
|---|---|---|
| `Core.lua` | Namespace, DB, events, Logger, Compat, State, Config, utilities | business logic, UI |
| `DataCollector.lua` | Collect/store local player data | UI, comm routing |
| `AttunementTracker.lua` | Quest attunement state | UI, comm |
| `CommSystem.lua` | Encode/chunk/send/receive/route addon messages | business logic of routed msg |
| `RecruitmentSystem.lua` | Auto-recruit + welcome logic | UI, comm internals |
| `WishlistSystem.lua` | Wishlists + loot prio data | UI, comm internals |
| `RaidTracker.lua` | Raid sessions, attendance, snapshot scores | UI |
| `LootTracker.lua` | Loot history recording | UI |
| `LootMaster.lua` | ML loot distribution (not on retail) | roster data |
| `TradeCouncil.lua` | Retail's loot council by trade: offers, answers, awards, the trade that records them (#185) | UI (UI/TradeCouncil.lua) |
| `RecipeTracker.lua` | Recipe scanning + sync | UI |
| `OfficerNotes.lua` | Officer note storage + sync | UI |
| `TrialTracker.lua` | Trial lifecycle + sync | UI |
| `GuildManager.lua` | Rank changes, kicks, MOTD/Info, inactivity, suggestions, action log | UI, comm |
| `GearAudit.lua` | Guild-wide enchant audit from synced gear | UI |
| `RaidTools.lua` | Composition + buff/cooldown coverage of group/online roster | UI |
| `ConsumableChecker.lua` | Detect flask/elixir/food buffs (TBC's; Midnight's flask, food, rune and my weapon on retail, unknown never missing, #187) | UI |
| `MythicPlus.lua` | Retail only: my keystone, Mythic+ rating and weekly vault, read through Compat and sent with my member data; formats a member's for the sheet and the roster (#187) | UI, comm internals |
| `SpecChecker.lua` | Detect talent spec | UI |
| `Journal.lua` | WoW: Forever only: what happened to my character (level milestones; dungeon clears later), the guild's journal as it arrives on the `journal` sync domain, the export's `journal` and the Discord opt-out (#205) | UI, the guild's feed (guildos.me) |
| `ChehulGossip.lua` | Forever and retail: the whisper gossip on `ChehulRecruit`, generic by topic: the peers heard, the whisper test, beacons, rounds and their ceilings (ADR-0029) | Recruitment rules, the shared mesh library |
| `RecruitBeacon.lua` | The ad on the network: `CR2` for old clients, `CR3` in the gossip, the caches, an officer's broadcast, what the client holds (the cache and the site's list) | UI |
| `GuildFinder.lua` | Every rule of the finder: the ad's one shape, its sources, filters, order, a raid night on the player's clock | UI (UI/GuildFinder.lua), the network |
| `JoinRequests.lua` | The request, from both sides: the guildless character's queue and `CRQ`, the guild's rows, `CRA`, the decision, the invite, the export's `joinRequests` | UI (UI/JoinRequests.lua) |
| `UI/Helpers.lua` | ALL UI components + theme (until split) | data logic, comms |
| `UI/RosterFrame.lua` | Roster window, tabs | data writes |
| `UI/MemberDetail.lua` | Per-member detail panel | data writes |
| `UI/ManagementPanel.lua` | "Liderança" tab UI (calls GuildManager) | data writes |
| `UI/FeaturePanels.lua` | Feature panels (raids/loot/etc.) | data writes |
| `UI/RecipesPanel.lua` | Recipes panel | data writes |
| `UI/RaidHUD.lua` | CD overlay + consumable popup | data writes |

---

## Load Order (GuildOS.toc)

| # | File | Depends on |
|---|------|------------|
| 1–5 | `Libs/*` | nothing |
| 6a | `Locales/Locale.lua` + `enUS/ptBR/esES/deDE/frFR/ruRU/koKR/zhCN/zhTW/itIT.lua` | Config — creates `GuildOS.L`; must load before any file that does `local L = GuildOS.L` |
| 6 | `Core.lua` | Libs — creates GuildOS global, Logger, Compat, State, Config |
| 7 | `DataCollector.lua` | GuildOS |
| 8 | `AttunementTracker.lua` | GuildOS, GuildOS.Compat |
| 9 | `CommSystem.lua` | GuildOS, GuildOS.State.comm |
| 10 | `RecruitmentSystem.lua` | GuildOS, GuildOS.CommSystem, GuildOS.State.recruitment |
| 11 | `WishlistSystem.lua` | GuildOS, GuildOS.CommSystem |
| 12 | `RaidTracker.lua` | GuildOS |
| 13 | `LootTracker.lua` | GuildOS |
| 14 | `LootMaster.lua` | GuildOS, GuildOS.LootTracker |
| 15 | `RecipeTracker.lua` | GuildOS, GuildOS.CommSystem |
| 16 | `OfficerNotes.lua` | GuildOS, GuildOS.CommSystem |
| 17 | `TrialTracker.lua` | GuildOS, GuildOS.CommSystem |
| 17a | `GuildManager.lua` | GuildOS, GuildOS.TrialTracker, GuildOS.RaidTracker |
| 18 | `ConsumableChecker.lua` | GuildOS |
| 19 | `SpecChecker.lua` | GuildOS |
| 20 | `UI/Helpers.lua` | GuildOS (creates GuildOS.UI) |
| 21 | `UI/RecipesPanel.lua` | GuildOS.UI |
| 22 | `UI/FeaturePanels.lua` | GuildOS.UI, GuildOS.RaidTracker, GuildOS.WishlistSystem |
| 23 | `UI/RosterFrame.lua` | GuildOS.UI, all data modules |
| 24 | `UI/MemberDetail.lua` | GuildOS.UI |
| 24a | `UI/ManagementPanel.lua` | GuildOS.UI, GuildOS.GuildManager |
| 25 | `UI/RaidHUD.lua` | GuildOS.UI, GuildOS.State.raidCD |
| 25a | `Core/Probe.lua` | GuildOS, GuildOS.Compat; loads with Core, starts in `MODULE_START` |
| 25b | `Modules/ChehulGossip.lua` | GuildOS, GuildOS.Compat, `_G.ChehulMesh`; before RecruitBeacon, which registers its topic |
| 25c | `Modules/GuildFinder.lua` | GuildOS, GuildOS.Compat |
| 25d | `Modules/RecruitBeacon.lua` | GuildOS, ChehulGossip; reads GuildFinder and CompanionImport when called |
| 25e | `Modules/JoinRequests.lua` | GuildOS, ChehulGossip, GuildFinder |
| 25f | `UI/RecruitBeacon.lua`, `UI/GuildFinder.lua`, `UI/JoinRequests.lua` | GuildOS.UI, the modules above |

**Start order** is `MODULE_START` in `Core/Core.lua`, not the TOC's: `RecruitBeacon`, whose one mesh handler feeds the gossip,
then `ChehulGossip`, `JoinRequests`, `GuildFinder`, `Probe`. `OFFICER_START` runs `JoinRequests:Refresh` once the rank is
known, because at `MODULE_START` it is not (#79): a request from the site read then reached no officer's notice.

---

## Data Flow

### Login pipeline

```
PLAYER_LOGIN
  │
  ├─► GuildOS:ResolveGuildDB()       — creates per-guild GuildOSDB[guildKey] → GuildOS.db
  └─► GuildOS:InitModules()          — initializes all enabled modules
        ├─► DataCollector:CollectMyData()
        └─► CommSystem:BroadcastMyData()
              ├─► DataCollector:GetBroadcastData()   → clean payload
              └─► CommSystem:SendMessage()            → compress/chunk/send
```

### Incoming message pipeline

```
CHAT_MSG_ADDON
  │
  └─► CommSystem:OnMessageReceived()
        ├─ reassemble chunks (GuildOS.State.comm.pendingMessages)
        ├─ decompress + deserialize
        └─ route by MSG_TYPE:
              BROADCAST  → DataCollector:StoreReceivedData()
              RAID_DATA  → RaidTracker:HandleIncoming()
              NOTES_ALL  → OfficerNotes:HandleAllIncoming()
              WL         → Wishlist:HandleWishlistBroadcast()
              RC         → RecipeTracker:HandleIncoming()
              TR         → TrialTracker:HandleIncoming()
              WC         → GuildOS.State.recruitment.welcomedRecently
              ...
```

### UI pipeline

```
GUILD_ROSTER_UPDATE  ──► RosterFrame:RefreshRoster()
Tab click            ──► FeaturePanels.ShowPanel(panelName)
Row click            ──► MemberDetail:Show(playerKey)
```

---

## Session State (GuildOS.State)

Runtime-only, never persisted. Defined in `Core.lua`:

```lua
GuildOS.State = {
    comm        = { lastBroadcast = 0, pendingMessages = {} },
    lootMaster  = { activeLoot, rolls, rollTimer, isMLSession, lootWindowOpen,
                    listeningForRolls, restrictedRollers, pendingTrades,
                    testMode, rollPattern, disenchanter },
    recruitment = { ticker, lastSend, knownMembers, rosterReady, welcomedRecently },
    raid        = { currentRaid, trackingActive, snapshotTimer, endTimer },
    consumables = { lastCheck },
    raidCD      = { state = {}, members = {} },   -- [playerName][cdKey], [name]=classFile
    tradeCouncil = { offers = { [id] = offer }, trade },  -- retail's loot council (#185)
}
```

---

## Config Accessors (Rule 8)

```lua
GuildOS:GetSetting("showOffline")          -- reads GuildOS.db.settings[key]
GuildOS:SetSetting("showOffline", true)    -- writes GuildOS.db.settings[key]
```

Never read/write `GuildOS.db.settings.*` directly from UI files.

---

## SavedVariables Schema (GuildOSDB[guildKey])

```lua
{
  version  = 1,
  settings = { sortBy, sortAsc, showOffline, minimap, officerMaxRank, officerMaxRankAt, modules,
               readyMinIlvl, readyMinIlvlAt },  -- Forever: the guild's minimum item level for a 60, on guildcfg/readymin (#206)
  members  = { ["Name-Realm"] = { name, realm, class, level, race, avgIlvl,
                                   gear, professions, attunements, stats, spec,
                                   mplus, vault,   -- retail: { rating, key = { map, level } },
                                                   -- { at, raid/dungeon/world = { n, best } } (#187)
                                   addonVersion, lastUpdate, lastSync } },
  myData   = {},              -- local player's CollectMyData snapshot
  altLinks = { [altKey] = mainKey },
  trials   = { [key] = { status, startDate, endDate, notes, snapshots } },
  officerNotes     = { [key] = { notes=[], tags={} } },
  managementLog    = [{ action, target, detail, author, timestamp }],  -- capped ring buffer (200)
  raidTracker      = { sessions, attendance, currentGroupTag, deletedSessions, openSession, openChar, mergedSessions },  -- mergedSessions: local only, never sent (#197)
  attendancePenalties = { LATE, LEFT_EARLY, NO_CONSUMES },  -- the guild's weights (CoreManager, #55); cores override
  lootHistory      = [{ itemLink, itemName, quality, player, playerKey, count, timestamp, raid, instanceID,
                        fromML }],  -- newest first, 500; retail's personal loot adds itemId, encounterID, no fromML,
                                    -- and its player is the whole Name-Realm, the key (#183); an award by
                                    -- trade sets awarded and from (the holder) on the winner's row (#185)
  lootMaster       = { rollDuration, autoAnnounce, wishlistOnlyMode, awardHistory },
  guildWishlists   = { [lowerName] = { name, class, wishlist=[] } },  -- retail: the lower-case whole key (#185)
  lootPrios        = { [itemId] = [{ name, class, order }] },
  wishlists        = { [charKey] = [{ itemId, itemLink, order, isOffspec }] },
  recruitment      = { enabled, interval, message, channels, welcomeEnabled,
                       welcomeMessage, discord, minRankIndex, postMaxRank },
                       -- minRankIndex gates the officer's own sending; postMaxRank (nil = every rank) is
                       -- the members' limit, sent in RI as maxRank and kept in guildRecruitment (#150)
  consumableChecks = { lastResults },
  recipes          = { [charKey] = { [canonProfName] = [{ name, spellId, itemId }] } },
  recipeScanTimes  = { [profName] = timestamp },
  journal          = { seq, entries = [{ id, subjectKey, at, type, data }] },  -- Forever: the guild's, 30 days, 1,000 (#205)
  founding         = { foundedAt, source, declaredBy, recordedAt, windowDays, manual, revision },  -- Forever (#208)
  foundingJoins    = { [key] = { joinedAt, src } },  -- each member's own claim, filed under its sender (#208)
  profile          = { prefRoles, feedOptOut },  -- feedOptOut: not named on Discord; also on my own members row (#205)
  recruitRelay     = { [guild] = cr2 },        -- CR2 ads heard, as sets, capped and expiry-pruned
  recruitAds       = { [key] = ad },           -- CR3 ads heard, GuildFinder's shape, capped at forty plus the guild's own (ADR-0029)
  joinRequests     = { [id] = { id, character, class, level, role, note, at, seen, status, source, gameId, relayedBy,
                                unheard, decidedBy, decidedAt } },  -- who asked this guild, fifty at most
}
```

### What sits beside the guilds, at the top of GuildOSDB

The account's, not a guild's, so it is one per SavedVariables file:

```lua
__companion     = "GOSCOMP1:...",  -- the one string the desktop companion lifts: the export with the guild's
                                   -- switch on, the character's own pack with it off (ADR-0028)
__companionAt   = 1791000000,      -- when the addon last wrote the EXPORT: never a pack
__companionSelf = true,            -- __companion is a pack, absent when it is the export
recruitOutbox   = { [character] = { [id] = request } },  -- a guildless character's own requests (ADR-0029)
recruitOutboxWire = "GOSOUTB1:...",   -- the open ones, written on logout for the companion to take to the site
guildFinder     = { locale, day, period, pace, focus, loot, trial, world, wantsMe },  -- the finder's filters
recruitAudit    = { gossip, requests, channel, at },   -- the Audit panel's numbers, kept; nothing goes to the site
probeChannel    = { timer, click, timerSkipped, clickSkipped, heard, joined, left, at },  -- /gos probe channel
probeChannelOpen = "GOSProbe1234",    -- the running probe's channel: one a /reload cut short is left from it
```

### Field conventions

| Convention | Rule |
|---|---|
| Player key | Always `"Name-Realm"` full string |
| Numeric fields | Always `0`; never `nil` |
| Boolean fields | `true` or `nil` in lookup tables |
| Time values | `GetTime()` return value |
| Percentages | `[0, 1]` stored; ×100 for display |
| Score values | `math.max(0, math.min(100, v))` |

---

## Communication Protocol

- Prefix: `"GuildOS"` (the loot council has its own over RAID: `GuildOSLM` on Forever and Anniversary, `GuildOSTC` on
  retail, plain `|`-separated text with the item link last; ADR-0026's #185 amendment)
- Format: `TYPE:PAYLOAD` → LibSerialize → LibDeflate compress → encode → chunk 230 bytes
- LibSerialize is Guild OS's own copy, `LibStub("GuildOS-LibSerialize")`, never the shared name: LibStub hands the
  highest minor to everyone, DBM-Core's minor 6 divides `1 / num`, and WoW: Forever raises on every division by
  zero, so with DBM on no message ever left (issue #87). `tools/libserialize-private.lua` guards it.
- Single ≤253 bytes: `S:<encoded>`
- Multi-chunk: `M:<msgId>:<idx>:<total>:<chunk>`
- Priority: `"BULK"` default — `"NORMAL"` only for time-sensitive (e.g. WELCOME_CLAIM)
- Sync sends go through `Compat.SendAddonMessage` (ChatThrottleLib underneath) and loot messages through `Compat.SendAddonMessageNow`; both act on the send result (ADR-0019)

### Message Types (CommSystem.MSG_TYPES)

| Code | Constant      | Description |
|------|---------------|-------------|
| BC   | BROADCAST     | Full member data broadcast |
| RQ   | REQUEST       | Request data from all |
| RS   | RESPONSE      | Response to request |
| PI   | PING          | Presence ping |
| PO   | PONG          | Presence pong + version |
| VR   | VERSION       | Version check |
| AL   | ALT_LINK      | Alt/main link table sync |
| RD   | RAID_DATA     | Raid session + attendance |
| RX   | RAID_DELETE   | Delete raid session tombstone |
| OA   | NOTES_ALL     | Bulk officer notes sync |
| WC   | WELCOME_CLAIM | Welcome claimed (suppress others) |
| WL   | (raw string)  | Wishlist broadcast |
| LP   | (raw string)  | Loot priorities broadcast |
| ON   | (raw string)  | Officer note broadcast |
| RC   | (raw string)  | Recipe broadcast |
| TR   | (raw string)  | Trial data broadcast |

**Who may send them (issue #78).** `WC`, `WI`, `LP`, `ON`, `OA`, `TR` and `RD` are believed only over
GUILD from a current officer (`IsOfficerByName(sender)`); `RX` and `AL` check the officer, and `RI` binds
trust to channel and sender in `Recruitment:ApplyIncoming`. Every legitimate sender of these is
officer-gated at the source and sends over GUILD. Since #81 `RX`, `AL`, `RR`, every officer
SyncService domain and the two domains whose handlers check the officer themselves (`alliance`,
`core.roster`, in `GUILD_ONLY_DOMAINS`) ask for GUILD as well. So does `journal` (#205), a member
domain: its handler keeps an entry only when its subject, localized, is the sender's key. Who is an officer is the guild's
choice: `officerMaxRank` changes go out stamped on the `guildcfg` domain, and every client keeps
the newest one an officer sent (#81).

### The recruitment's prefix (ADR-0029, specs/071 in guildos-web)

`ChehulRecruit` on the shared mesh, plain `|`-separated text, and everything arriving goes to `Gossip:Receive` first: what
nobody routes there (CR2 above all) goes back to `RecruitBeacon`. Forever and retail; Anniversary keeps CR2 alone.

| Message | Goes by | What it is |
|---|---|---|
| `CR2\|guild\|faction\|needs\|days\|note\|langs\|focus\|version\|expiry\|author` | GUILD, YELL | The old ad, for clients that predate CR3. Believed as heard, never verified |
| `CR3\|name\|f\|w\|p\|d\|s\|e\|pc\|l\|fo\|r\|c\|lo\|t\|ct\|u\|v\|x` | WHISPER, GUILD | The full ad, the site's `GosrecrAd`. No removal: it leaves by `x`, cut to 72 hours ahead on the way in. The guild's own only over GUILD from an officer |
| `CRB\|ad\|version\|guild\|officer` | GUILD, group, YELL | The beacon, every `BEACON_SECONDS`, from every client: presence, one ad in turn, and the sender's guild while it holds that guild's ad |
| `CRD\|name:v,name:v,...` | WHISPER | A digest, `DIGEST_MAX` pairs: the `DIGEST_NEWEST` newest, then the rest in rotation |
| `CRG\|name` | WHISPER | Asks for one CR3 |
| `CRP\|name,name,...` | WHISPER | `PEX_MAX` peers heard lately, read only from who I sent a digest this round |
| `CRQ\|id\|character\|class\|level\|role\|guild\|note` | WHISPER, GUILD | A request, repeated every 300 seconds while the player is online; over GUILD, a guildmate passing it on |
| `CRA\|id\|state\|who` | WHISPER, GUILD | The answer: `officer` and `member` say where it got to and do not stop the repetition, `invited` and `declined` end it. Only an officer's word over GUILD closes a row |
| `CRW\|token\|try` | WHISPER, to myself | The whisper test. The token lives the session, so a late echo still counts |

What a client offers is what it holds of its own faction and region, the guild's own ad always: the CR3 cache and the
live ads of the site's list, which is copied into nobody's
cache. The seal comes from one's own `GOSRECR1` alone, and nothing in a message can turn it on.

---

## UI Architecture

- All UI factory functions live in `GuildOS.UI` (from `UI/Helpers.lua`)
- Theme colors in `C` table (local alias inside each UI file)
- Main window: `GuildOS.RosterFrame` (frame `GuildOSWindow`, `UI/Window.lua`) — the one window; every registry feature with `tab` is a tab (ADR-0016)
- Virtual scroll (lists): `FauxScrollFrameTemplate` + `FauxScrollFrame_Update/GetOffset`
- Content scroll (panels): `UIPanelScrollFrameTemplate`
- All scroll bars skinned with `UI:SkinScrollBar()` (6px accent track)
- Reusable widgets: `UI:CreateButton()`, `UI:CreateHeaderText()`, `UI:CreateCloseButton()`, `UI:CreateText()`
- UI callbacks must call module methods — zero business logic inline

## Permission Model

- `GuildOS:IsOfficer()` → local rank ≤ `officerMaxRank` setting
- `GuildOS:IsOfficerByName(name)` → validates sender of officer-only comm messages
- Officer-only features: trials, recruitment, officer notes, alt links, loot prios
