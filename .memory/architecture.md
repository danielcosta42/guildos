# BRutus — Architecture

_Last updated: 2026-04-26_

---

## Design Principles

1. **Single global namespace** — `BRutus` only. All sub-modules are nested tables.
2. **Separation of concerns** — each file owns exactly one responsibility.
3. **Defensive coding** — every API call that may not exist is guarded via `BRutus.Compat`.
4. **Classic-first compatibility** — no API is called outside `BRutus.Compat` if it may vary by version.
5. **No UI in the data pipeline** — data modules have zero UI dependencies.
6. **One-way data flow** — `Game Events → Modules → State/DB → UI reads`.

---

## Target Folder Structure

```
BRutus/
  BRutus.toc              — load order, SavedVariables declaration
  Core.lua                — BRutus global, DB defaults, events, slash cmds, utilities,
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
    Locale.lua            — BRutus.L bootstrap (metatable fallback to English key)
    enUS.lua              — master/stub (English is implicit)
    ptBR.lua esES.lua deDE.lua frFR.lua — translations (guarded by GetLocale)
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

Until that split is done, all UI code continues to use `BRutus.UI` / the `UI` local alias.

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
| `LootMaster.lua` | ML loot distribution | roster data |
| `RecipeTracker.lua` | Recipe scanning + sync | UI |
| `OfficerNotes.lua` | Officer note storage + sync | UI |
| `TrialTracker.lua` | Trial lifecycle + sync | UI |
| `GuildManager.lua` | Rank changes, kicks, MOTD/Info, inactivity, suggestions, action log | UI, comm |
| `GearAudit.lua` | Guild-wide enchant audit from synced gear | UI |
| `RaidTools.lua` | Composition + buff/cooldown coverage of group/online roster | UI |
| `ConsumableChecker.lua` | Detect flask/elixir/food buffs | UI |
| `SpecChecker.lua` | Detect talent spec | UI |
| `UI/Helpers.lua` | ALL UI components + theme (until split) | data logic, comms |
| `UI/RosterFrame.lua` | Roster window, tabs | data writes |
| `UI/MemberDetail.lua` | Per-member detail panel | data writes |
| `UI/ManagementPanel.lua` | "Liderança" tab UI (calls GuildManager) | data writes |
| `UI/FeaturePanels.lua` | Feature panels (raids/loot/etc.) | data writes |
| `UI/RecipesPanel.lua` | Recipes panel | data writes |
| `UI/RaidHUD.lua` | CD overlay + consumable popup | data writes |

---

## Load Order (BRutus.toc)

| # | File | Depends on |
|---|------|------------|
| 1–5 | `Libs/*` | nothing |
| 6a | `Locales/Locale.lua` + `enUS/ptBR/esES/deDE/frFR.lua` | Config — creates `BRutus.L`; must load before any file that does `local L = BRutus.L` |
| 6 | `Core.lua` | Libs — creates BRutus global, Logger, Compat, State, Config |
| 7 | `DataCollector.lua` | BRutus |
| 8 | `AttunementTracker.lua` | BRutus, BRutus.Compat |
| 9 | `CommSystem.lua` | BRutus, BRutus.State.comm |
| 10 | `RecruitmentSystem.lua` | BRutus, BRutus.CommSystem, BRutus.State.recruitment |
| 11 | `WishlistSystem.lua` | BRutus, BRutus.CommSystem |
| 12 | `RaidTracker.lua` | BRutus |
| 13 | `LootTracker.lua` | BRutus |
| 14 | `LootMaster.lua` | BRutus, BRutus.LootTracker |
| 15 | `RecipeTracker.lua` | BRutus, BRutus.CommSystem |
| 16 | `OfficerNotes.lua` | BRutus, BRutus.CommSystem |
| 17 | `TrialTracker.lua` | BRutus, BRutus.CommSystem |
| 17a | `GuildManager.lua` | BRutus, BRutus.TrialTracker, BRutus.RaidTracker |
| 18 | `ConsumableChecker.lua` | BRutus |
| 19 | `SpecChecker.lua` | BRutus |
| 20 | `UI/Helpers.lua` | BRutus (creates BRutus.UI) |
| 21 | `UI/RecipesPanel.lua` | BRutus.UI |
| 22 | `UI/FeaturePanels.lua` | BRutus.UI, BRutus.RaidTracker, BRutus.WishlistSystem |
| 23 | `UI/RosterFrame.lua` | BRutus.UI, all data modules |
| 24 | `UI/MemberDetail.lua` | BRutus.UI |
| 24a | `UI/ManagementPanel.lua` | BRutus.UI, BRutus.GuildManager |
| 25 | `UI/RaidHUD.lua` | BRutus.UI, BRutus.State.raidCD |

---

## Data Flow

### Login pipeline

```
PLAYER_LOGIN
  │
  ├─► BRutus:ResolveGuildDB()       — creates per-guild BRutusDB[guildKey] → BRutus.db
  └─► BRutus:InitModules()          — initializes all enabled modules
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
        ├─ reassemble chunks (BRutus.State.comm.pendingMessages)
        ├─ decompress + deserialize
        └─ route by MSG_TYPE:
              BROADCAST  → DataCollector:StoreReceivedData()
              RAID_DATA  → RaidTracker:HandleIncoming()
              NOTES_ALL  → OfficerNotes:HandleAllIncoming()
              WL         → Wishlist:HandleWishlistBroadcast()
              RC         → RecipeTracker:HandleIncoming()
              TR         → TrialTracker:HandleIncoming()
              WC         → BRutus.State.recruitment.welcomedRecently
              ...
```

### UI pipeline

```
GUILD_ROSTER_UPDATE  ──► RosterFrame:RefreshRoster()
Tab click            ──► FeaturePanels.ShowPanel(panelName)
Row click            ──► MemberDetail:Show(playerKey)
```

---

## Session State (BRutus.State)

Runtime-only, never persisted. Defined in `Core.lua`:

```lua
BRutus.State = {
    comm        = { lastBroadcast = 0, pendingMessages = {} },
    lootMaster  = { activeLoot, rolls, rollTimer, isMLSession, lootWindowOpen,
                    listeningForRolls, restrictedRollers, pendingTrades,
                    testMode, rollPattern, disenchanter },
    recruitment = { ticker, lastSend, knownMembers, rosterReady, welcomedRecently },
    raid        = { currentRaid, trackingActive, snapshotTimer, endTimer },
    consumables = { lastCheck },
    raidCD      = { state = {}, members = {} },   -- [playerName][cdKey], [name]=classFile
}
```

---

## Config Accessors (Rule 8)

```lua
BRutus:GetSetting("showOffline")          -- reads BRutus.db.settings[key]
BRutus:SetSetting("showOffline", true)    -- writes BRutus.db.settings[key]
```

Never read/write `BRutus.db.settings.*` directly from UI files.

---

## SavedVariables Schema (BRutusDB[guildKey])

```lua
{
  version  = 1,
  settings = { sortBy, sortAsc, showOffline, minimap, officerMaxRank, modules },
  members  = { ["Name-Realm"] = { name, realm, class, level, race, avgIlvl,
                                   gear, professions, attunements, stats, spec,
                                   addonVersion, lastUpdate, lastSync } },
  myData   = {},              -- local player's CollectMyData snapshot
  altLinks = { [altKey] = mainKey },
  trials   = { [key] = { status, startDate, endDate, notes, snapshots } },
  officerNotes     = { [key] = { notes=[], tags={} } },
  managementLog    = [{ action, target, detail, author, timestamp }],  -- capped ring buffer (200)
  raidTracker      = { sessions, attendance, currentGroupTag, deletedSessions },
  lootHistory      = [{ itemId, itemLink, playerName, raidName, timestamp }],
  lootMaster       = { rollDuration, autoAnnounce, wishlistOnlyMode, awardHistory },
  guildWishlists   = { [lowerName] = { name, class, wishlist=[] } },
  lootPrios        = { [itemId] = [{ name, class, order }] },
  wishlists        = { [charKey] = [{ itemId, itemLink, order, isOffspec }] },
  recruitment      = { enabled, interval, message, channels, welcomeEnabled,
                       welcomeMessage, discord, minRankIndex },
  consumableChecks = { lastResults },
  recipes          = { [charKey] = { [canonProfName] = [{ name, spellId, itemId }] } },
  recipeScanTimes  = { [profName] = timestamp },
}
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

- Prefix: `"BRutus"`
- Format: `TYPE:PAYLOAD` → LibSerialize → LibDeflate compress → encode → chunk 230 bytes
- Single ≤253 bytes: `S:<encoded>`
- Multi-chunk: `M:<msgId>:<idx>:<total>:<chunk>`
- Priority: `"BULK"` default — `"NORMAL"` only for time-sensitive (e.g. WELCOME_CLAIM)
- All sends via `ChatThrottleLib:SendAddonMessage`

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

---

## UI Architecture

- All UI factory functions live in `BRutus.UI` (from `UI/Helpers.lua`)
- Theme colors in `C` table (local alias inside each UI file)
- Main window: `BRutus.RosterFrame` — tabs: roster, tmb, raids, loot, trials*, recruitment*, settings*
- Virtual scroll (lists): `FauxScrollFrameTemplate` + `FauxScrollFrame_Update/GetOffset`
- Content scroll (panels): `UIPanelScrollFrameTemplate`
- All scroll bars skinned with `UI:SkinScrollBar()` (6px accent track)
- Reusable widgets: `UI:CreateButton()`, `UI:CreateHeaderText()`, `UI:CreateCloseButton()`, `UI:CreateText()`
- UI callbacks must call module methods — zero business logic inline

## Permission Model

- `BRutus:IsOfficer()` → local rank ≤ `officerMaxRank` setting
- `BRutus:IsOfficerByName(name)` → validates sender of officer-only comm messages
- Officer-only features: trials, recruitment, officer notes, alt links, loot prios
