# BRutus — Architectural Decision Records

_Last updated: 2026-04-26_

Architectural Decision Records (ADRs) for BRutus.
This is the canonical record of WHY the codebase is structured as it is.
Add a new ADR whenever you introduce a significant architectural pattern or change.

---

## ADR-0001 — Single `BRutus` global namespace

### Context
WoW addons share a global environment. Name collisions between addons are a real hazard.
Classic TBC clients do not support modern Lua module systems or table-passing via `...`.

### Decision
Create exactly one global: `BRutus`. All modules attach as sub-tables (`BRutus.CommSystem`, `BRutus.UI`, etc.).
`Core.lua` is the only file that creates the global; all other files assume it exists.

### Consequences
- (+) One global to audit; no accidental global leakage.
- (+) Compatible with all WoW Classic client versions.
- (+) Sub-modules can alias locally: `local RT = BRutus.RaidTracker`.
- (−) Modules must be loaded in the correct order. Enforced by `.toc`.

---

## ADR-0002 — Per-guild SavedVariables key

### Context
A single BRutus installation may be used on multiple guilds (server transfers, alts in different guilds).
Mixing guild data in a single flat DB would contaminate one guild's data with another's.

### Decision
`BRutusDB` uses a `"GuildName-Realm"` key as the top-level partition.
`BRutus:ResolveGuildDB()` creates or retrieves the guild-specific sub-table and stores it as `BRutus.db`.
All modules read/write `BRutus.db`, never `BRutusDB` directly.

### Consequences
- (+) Complete data isolation per guild per realm.
- (+) Migrations only need to handle one sub-table at a time.
- (−) If a player changes guilds, old guild data remains in `BRutusDB` until cleared manually.

---

## ADR-0003 — Cross-version compatibility layer (`BRutus.Compat`)

### Context
TBC Anniversary uses a different API surface than progressive Classic or Retail.
`C_ChatInfo`, `C_QuestLog`, `C_GuildInfo`, and `C_Timer` may or may not be present.
Inline version checks scattered across modules would become unmanageable.

### Decision
All version-sensitive API calls go through `BRutus.Compat` wrappers (defined in `Core.lua`).
No module other than `Core.lua` may check for `C_ChatInfo`, `C_QuestLog`, etc. directly.

### Consequences
- (+) Single place to update when APIs change across patches.
- (+) All feature modules are version-agnostic.
- (+) Wrappers return nil on unavailability; callers guard with `if result then`.
- (−) Slight indirection; performance overhead is negligible.

---

## ADR-0004 — CommSystem with LibSerialize + LibDeflate + ChatThrottleLib

### Context
WoW addon messages have a 255-byte channel limit. Guild roster data (gear, attunements, recipes)
far exceeds this. Sending raw Lua table representations would produce large strings.

### Decision
All outgoing messages are:
1. Serialized with LibSerialize (compact binary format)
2. Compressed with LibDeflate (further reduces size)
3. Encoded for addon channel (safe ASCII)
4. Chunked into ≤230-byte pieces (leaving room for `M:<msgId>:<idx>:<total>:` prefix)
5. Throttled via ChatThrottleLib to avoid disconnects

Receiving end reassembles chunks (keyed by msgId), then reverses the pipeline.
`BRutus.State.comm.pendingMessages` holds in-flight chunk sets.

### Consequences
- (+) Can send any size payload safely.
- (+) ChatThrottleLib prevents server-side throttle kicks.
- (−) Adds 3 library dependencies (LibSerialize, LibDeflate, ChatThrottleLib).
- (−) Small messages still go through the full pipeline (acceptable overhead).

---

## ADR-0005 — Session state in `BRutus.State` (not as module member vars)

### Context
Early versions stored session state as module-level member vars (e.g. `LootMaster.activeLoot`,
`CommSystem.lastBroadcast`). These are reset on `/reload` anyway but pollute the module table
with non-persistent data, making it unclear what is saved and what is runtime-only.

### Decision
All runtime-only, non-persistent data lives in `BRutus.State` (a table created in `Core.lua`).
Sub-tables mirror module ownership: `BRutus.State.comm`, `BRutus.State.lootMaster`, etc.
Module tables only contain methods and constants.

### Consequences
- (+) Clear boundary: `BRutus.db.*` = persisted, `BRutus.State.*` = runtime-only.
- (+) Easier to inspect/reset session state in one place.
- (+) Module tables are cleaner (methods only).
- (−) Slightly more verbose access path: `BRutus.State.lootMaster.activeLoot`.

---

## ADR-0006 — No centralized event pub/sub (yet)

### Context
AutoRaidCoach uses a centralized `Events.lua` pub/sub system where all game events route
through a single frame and modules subscribe with `On(eventName, fn)`.
BRutus predates this pattern and has event frames scattered across modules.

### Decision
BRutus does NOT yet have a centralized event system.
Each module creates its own event frame inside `Initialize()` for the events it needs.
The `BRutus` frame in `Core.lua` handles core events (PLAYER_LOGIN, GUILD_ROSTER_UPDATE, etc.).

**Future direction**: Extract to a centralized `Events.lua` when the module count grows enough
to justify the refactor. An ADR will be added at that point.

### Consequences
- (+) Simpler to reason about per-module event scope.
- (+) No risk of one module's handler affecting another.
- (−) Multiple frames registered for the same event (minor overhead).
- (−) No built-in decoupling between event source and handlers.

---

## ADR-0007 — Config accessors (`BRutus:GetSetting` / `BRutus:SetSetting`)

### Context
UI callbacks were directly reading/writing `BRutus.db.settings.*`. This tightly couples UI files
to the internal SavedVariables structure and makes future schema migrations harder.

### Decision
All reads and writes of `BRutus.db.settings.*` go through:
```lua
BRutus:GetSetting(key)        -- reads BRutus.db.settings[key]
BRutus:SetSetting(key, value) -- writes BRutus.db.settings[key]
```
UI files must use these accessors. Only `Core.lua` accesses `BRutus.db.settings` directly
(to define defaults and implement the accessors).

### Consequences
- (+) Schema migrations only require updating `GetSetting`/`SetSetting`.
- (+) UI files have no direct dependency on SavedVariables key names.
- (−) Marginal overhead (function call vs direct table access).

---

## ADR-0008 — UI component factory in `UI/Helpers.lua`

### Context
Each panel file was independently creating frames, applying backdrops, and styling text.
This produced duplicated code and inconsistent visual results.

### Decision
`UI/Helpers.lua` is the single source of truth for UI component creation:
`UI:CreateButton()`, `UI:CreateText()`, `UI:CreateHeaderText()`, `UI:CreateCloseButton()`,
`UI:SkinScrollBar()`, and the `C` color table.
Panel files must use these factory functions and never inline backdrop or font logic.

**Future direction** (see `architecture.md` — Target UI split):
Split `UI/Helpers.lua` into `UI/Theme.lua` (colors, no frames) and `UI/Core.lua` (factory functions),
keeping `UI/Helpers.lua` as a thin backward-compat shim.

### Consequences
- (+) Visual consistency enforced at the factory level.
- (+) Color theme changes require updating only one file.
- (+) Panel files are simpler and more readable.
- (−) `UI/Helpers.lua` currently mixes theme and factory responsibilities (known tech debt).

---

## ADR-0009 — Business logic in data modules, not UI callbacks (Rule 10)

### Context
`UI/RaidHUD.lua` had combat log parsing inline in `SetScript("OnEvent")`.
`UI/FeaturePanels.lua` had the full attendance score calculation inline.
This duplicated logic from `RaidTracker.lua` and made the code hard to test or reuse.

### Decision
All business logic lives in the data module that owns the domain:
- Score calculation → `RaidTracker:GetSnapshotScore()`
- Combat CD tracking → `HandleCombatLogCD()` (named function, called from SetScript)
- Welcome dedup logic → `Recruitment:HandleGuildJoin()`

UI callbacks are one-liner delegations or at most simple display logic (color selection, text formatting).

### Consequences
- (+) Logic is reusable from multiple UI panels.
- (+) Data module unit-testable in isolation.
- (+) UI callbacks are readable and predictable.
- (−) Requires discipline to resist the temptation of "just putting it here for now".

---

## ADR-0010 — Leadership Suite (`GuildManager`) split from its UI

### Context
Guild leaders needed quality-of-life management tools (rank changes, kicks,
MOTD/Info editing, inactivity purge, promotion suggestions). The pre-existing
right-click promote/demote was GM-only, single-step, unconfirmed, and had no
panel. The value-add is combining GuildOS-only data (raid attendance, trial
progress, last-online) with management actions.

### Decision
Add a dedicated logic module `Modules/GuildManager.lua` and a thin UI tab
`UI/ManagementPanel.lua` ("Liderança"), following Rule 3 / Rule 10:
- **All** guild API calls (GuildPromote/Demote/Uninvite/GuildSetMOTD/
  SetGuildInfoText) and the action log live in `GuildManager`.
- The panel and the roster context menu only *call* `GuildManager` methods.
- Permission gating uses the live `Can*` guild APIs (CanGuildPromote/Demote/
  Remove, CanEditMOTD/GuildInfo) — nil-guarded — **not** `IsGuildLeader()`, so
  officers with delegated rights get the actions too.
- A local, capped (200) `db.managementLog` records MOTD/Info changes for
  officer accountability. It is **not** synced over comm (local audit only).

### Protected-function constraint (discovered in TBC Anniversary)
`GuildPromote`, `GuildDemote`, and `GuildUninvite` are **restricted/protected**
functions: only Blizzard's untainted UI may call them. Any addon call raises
`ADDON_ACTION_FORBIDDEN` and does nothing — and there is **no** hardware-event
escape (unlike `InviteUnit` / `RandomRoll`, which the addon does call from
clicks). Confirmed in-client (v0.2.x) and by community sources.

Therefore `Promote`/`Demote`/`SetRank`/`Kick` do **not** call the restricted
API. They route to `GuildManager:_protectedNotice()`, which prints a clear
message and hands the leader off to the native guild panel via
`BRutus._origToggleGuildFrame` (captured in `Core:HookGuildFrame`). The
"intelligence" (inactivity report, promotion/trial suggestions) and the
non-protected actions (`SetMOTD`, `SetGuildInfo`, trial approve/deny) run
in-addon as normal.

### Consequences
- (+) The advisory layer (who to promote / who is inactive) is the real value
  and works fully; the final privileged click is a one-step native handoff.
- (+) No more `ADDON_ACTION_FORBIDDEN` errors.
- (−) Rank changes / kicks cannot be one-click from the addon — a hard Blizzard
  limitation, not a design choice.
- (−) The action log is per-officer (not shared); intentional for v1 simplicity.

---

## ADR-0011 — Localization (`BRutus.L`, English-key, metatable fallback)

### Context
The addon was originally Brazilian Portuguese with strings hardcoded and mixed
PT/EN throughout. To serve a general (international) audience it needed full i18n
with English as the default and additional languages.

### Decision
Add a lightweight localization layer (no Ace/LibStub dependency):
- `Locales/Locale.lua` creates `BRutus.L = setmetatable({}, { __index = function(_, k) return k end })`.
  Keys are the **canonical English strings used directly in source** (`L["Roster"]`),
  so a missing translation falls back to readable English (never nil, no symbolic
  key leakage). `BRutus.Locale = GetLocale()`.
- Loaded **right after `Config.lua`** (before any file that aliases `local L = BRutus.L`).
- One data file per locale: `enUS.lua` is a stub (English implicit via metatable);
  `ptBR.lua`, `esES.lua` (esES+esMX), `deDE.lua`, `frFR.lua` early-return unless
  `GetLocale()` matches, then assign `L["English key"] = "translation"`.
- All player-facing literals across the codebase were converted to `L["..."]`.
  Format specifiers (`%d`/`%s`) and WoW markup (`|cff..|r`, `|T..|t`) stay **inside**
  the key. Protocol strings, slash-command tokens, debug output, texture/font paths,
  and the "Guild OS" brand are NOT localized.
- `GetLocale` added to `.luacheckrc read_globals`.

### Consequences
- (+) English default → serveable to a general audience; PT preserved as a locale.
- (+) Adding a language = drop one `xxYY.lua` file; no source changes.
- (+) Graceful degradation: untranslated keys show English, never break.
- (−) English keys are the lookup identity, so editing an English string requires
  updating that key in every locale file (coverage validated by extracting source
  `L["..."]` keys and diffing against each locale).
- (−) Non-EN/PT translations are machine-generated (v1) — fine to ship, native
  review recommended before a polished release.

---

## ADR-0012 — Start-up isolation and capability misses

### Context
WoW: Forever (beta 2026-09-17) is a new client whose API surface is unknown until it opens.
`BRutus:InitModules` called ~50 `Initialize()` functions in sequence with no isolation, so one
missing API made one module raise and left every later module unstarted. `RegisterEvent` on an
event the client does not know and `HookScript` on a tooltip script the frame lacks raise too.

### Decision
- Start-up is a list (`MODULE_START`, `OFFICER_START` in `Core.lua`) run through
  `BRutus:RunStartup`, which `xpcall`s each step (keeping the stack) and records the failure against the module and
  the feature/window it backs. Failed windows refuse to open with a message.
- Events are registered through `BRutus.Compat.RegisterEvent`, tooltip scripts hooked through
  `BRutus.Compat.HookTooltip`; a miss is recorded once in `State.missing`.
- Failures and misses land in the `/guildos errors` ring; one login line appears only when
  there was at least one.
- Exceptions: the `Core.lua` bootstrap frame, `ChehulNet.lua` (shared verbatim across addons)
  and the companion files' file-scope registrations loaded by `tools/` harnesses.

### Consequences
- (+) A missing API costs one feature, not the addon; the tester sees which one and why.
- (+) One place (the start list) to mark modules per client — used by client detection (#7).
- (−) A failure inside `Initialize` can leave that module half-initialized (frames created,
  events registered). Its window is blocked, but its already-registered handlers may still run.
- (−) New `RegisterEvent` call sites must remember to use `Compat.RegisterEvent`.

---

## ADR-0013 — Forever skin: tokens with legacy aliases, one font helper

### Context
The "Obsidian" theme (violet accent, champagne gold, FRIZQT everywhere) matched neither guildos.me
nor WoW: Forever. About 2,000 call sites read `BRutus.Colors`, and 242 `SetFont` calls used
`Fonts\\FRIZQT__.TTF`.

### Decision
- `BRutus.Colors` carries the 17 tokens from the design handoff. The legacy keys the screens read
  stay, each a copy of the token that plays its role, so the whole UI re-skins without touching its
  call sites. Gold is the only accent and the only colour allowed as a background; violet only means
  epic quality. The accent picker (`ACCENT_PRESETS`, `ApplyTheme`) is removed.
- Four OFL fonts ship in `Media/Fonts`. Every font goes through `BRutus:ApplyFont`, which enforces
  serif only from 14px, mono clamped to 10px and no outline. CI rejects `FRIZQT__` in Lua.

### Consequences
- (+) One table and one helper decide the look; the screen slices (#15–#17) only lay things out.
- (+) Class and quality colours stay with the game (`RAID_CLASS_COLORS`, `GetItemQualityColor`).
- (−) Legacy keys keep old names with new meanings (`silver` is warm now); new code uses the tokens.
- (−) 187 text requests at 7–9px (65 direct SetFont calls, 114 through CreateText/CreateHeaderText, 8
  through CorePanel's MakeLabel) now render at 10px, and no text keeps an outline (158 direct SetFont
  calls and every text helper had one); dense layouts need a visual pass.
- (−) The fonts add about 800 KB to the package, and a newly added font needs a client restart.

---

## ADR-0014 — Client detection: two signals for Anniversary, TBC content absent elsewhere

### Context
Nothing asked which client GuildOS runs on. WoW: Forever (internal build 1.60.x) is in the Classic family
but carries none of the TBC content, and `WOW_PROJECT_ID` has no Forever value yet, so a project-id switch
would be a guess, and a guess that reads "retail" would be worse than none.

### Decision
- `BRutus.Client` in `Core/Compat.lua`, computed once at load: the `GetBuildInfo` fields, `projectId` for
  diagnostics, `isAnniversary` and the `has` capability flags (`secrets`, `chatLockdown`, `tradeSkillUI`,
  `tooltipData`, `guildSetNote`).
- `isAnniversary` needs both `WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC` and an interface in
  20500–29999. Everything else, an unknown client included, is "not Anniversary". There is no flavour field.
- TBC content is absent outside Anniversary rather than disabled: `AttunementTracker.lua` and
  `ConsumableChecker.lua` return before defining their global, so every existing `if BRutus.X then` guard
  reads it as missing. Registry features, audit sub-tabs and the TBC-only raid cooldowns in Raid Tools
  (Bloodlust/Heroism, Misdirection) carry `tbc = true`. The raid cooldown HUD (never created, combat log
  never registered), the member detail attunement section and the wishlist raid catalogue check
  `isAnniversary` directly. The `/gos help` lines and the Settings consumable test appear only where
  their module exists. The player's toggles are never read or written for this.
- The companion export keeps its shape: guildos-web requires `attunements` and `att25`, which are `[]`
  and `0` outside Anniversary.

### Consequences
- (+) One table answers "which client, what can it do" for #9 (`/guildos probe`) and #10 (compat loop).
- (+) Almost no new guards: the call sites that read the attunement and consumable modules already check
  that the module exists; only RosterFrame's member tooltip and `/gos attune dumpquests` did not.
  AuditPanel's attunement grid reads the tracker unguarded too, but only inside the sub-tab that is not
  built outside Anniversary.
- (−) A module file that returns early is invisible to `/guildos errors`: it did not fail, it is not there.
- (−) Nothing names Forever itself; add a field when a feature needs to tell Forever from an unknown client.

---

## ADR-0015 — `/guildos probe`: one guarded snapshot of the client, kept in SavedVariables

### Context
Most of what decides the Forever port is unknown until the beta opens: the interface, the project id,
Secret Values, chat lockdown in instances, roster name shapes, and which of the APIs and events GuildOS
uses exist. Collecting that by hand is an hour of `/dump` per tester, retyped into a message.

### Decision
- `Core/Probe.lua` holds the inventory as data (`Probe.APIS`, `TEMPLATES`, `SCRIPTS`, `EVENTS`) and
  `Probe:Run()`, reached through `/guildos probe`.
- The result is `GuildOSDB.probe`: one top-level key, overwritten each run, timestamped. It is written to
  disk on `/reload` or logout like any SavedVariable, so a tester sends one file.
- Every read goes through `pcall`. A missing API is recorded as missing; a raising one keeps its error
  text. Events are tried on one throwaway frame and released at once. Templates are asked through
  `C_XMLUtil.GetTemplateInfo` where the client has it; only without it is a named `CreateFrame` tried and
  hidden right away.
- Secret Values are reported from `C_Secrets.HasSecretRestrictions()`, the build's own answer. That the API
  exists says nothing: 2.5.6 already ships it.
- The GUILD test message goes out on its own prefix, `GuildOSProbe`, so other GuildOS clients never
  parse it. Nothing is sent outside a guild, and nothing runs in combat.
- Privacy: the snapshot stores one guild member's name (the first roster row) and the realm. It never
  stores the notes that come back in the same row.
- `tools/probe.lua` fails when the addon's source registers an event that `Probe.EVENTS` does not list,
  so the inventory cannot quietly fall behind the code.

### Consequences
- (+) A beta tester runs one command and sends back one file; the port's open questions become data.
- (+) The same snapshot works on Anniversary today, as a baseline to compare the beta against.
- (−) The API list is maintained by hand. Only the event list is checked against the source.
- (−) Load-on-demand frames (`GuildFrame`, `CommunitiesFrame`, `WorldMapFrame`) read as missing until
  they have been opened once; the summary cannot tell that apart from a client without them.
- (−) On a client without `C_XMLUtil`, each run creates up to nine hidden template frames that live until
  the UI reloads.

---

## ADR-0016 — One window: every feature a tab, reorganised by width

### Context
Three containers did overlapping jobs: the hub (`UI/Hub.lua`, a 430px card), one floating window per feature
(`UI/Window.lua`) and the expanded frame (`UI/RosterFrame.lua`, 1236×844, every feature a tab, fixed size).
Entry points opened different ones, the Leadership deep links the hub sent were silently dropped, and the
Forever handoff (§6) specifies one window that reorganises by width.

### Decision
- One window, `BRutus.RosterFrame` (frame `GuildOSWindow`), built in `UI/Window.lua`. Every registry feature
  with `tab` is a tab, and its panel builds the first time the tab opens. The registry's `hub` flag, the
  per-feature window sizes and the window stacking code are gone.
- One way in: `UI:OpenWindow(id, sub, filter)` and `UI:ToggleMain()`. The slash commands, the minimap, the guild-frame
  takeover and a new key binding (unbound by default) all use them. A disabled, failed or officer-only feature
  is refused with its own message. `sub` and `filter` go through the panel's `SelectSub`, which every panel with
  sub-tabs now exposes, to a sub-panel's `ApplyFilter` where it has one (the calendar takes a day).
- The band is measured on the content area, the panel that hosts every tab's tables, not on the window
  (`UI.LADDER`, `UI:ResolveBand`, 16px hysteresis). Tabs that do not fit fold
  into "»n" (`UI:FitTabs`; never icon-only, and the open tab always stays on the rule). Under 520px a one-line
  selector replaces the rule and the content switches to Now; under 420px only the 28px bar stays, with online
  · time to raid · pending. Panels measure their own width for their own columns (#15–#17).
- The bar band is a height as well as a width: letting go of the grip there, or minimising, folds the window to
  28px and remembers its size; the way back out restores it.
- `settings.window` keeps `left`, `top`, `w`, `h`, the open tab and the fold. A saved rectangle is pulled onto
  the current screen (`UI:ClampWindowRect`). The switch to Now under 520px is not saved as a choice.
- The first tab keeps the id `home`, which saved settings and the fall-back already use, and is labelled Now. It
  is the hub's live column (`UI/Agora.lua`): the next raid, what needs this player, the last 48 hours. The home
  cards sit beside it from 780px until #15 replaces them.

### Consequences
- (+) Every entry point lands in the same window, and a deep link reaches its sub-tab.
- (+) One code path for tabs, persistence and scale, tested offline by `tools/window-shell.lua`.
- (−) One feature on screen at a time: two screens side by side are no longer possible.
- (−) A panel not yet redesigned for the narrow bands is clipped at the window edge until its screen issue lands.
- (−) Rows for loot, trials and raid sessions open their screen without a narrower filter: those screens have none yet.
- (−) The Now column shows only what the modules store today: unowned loot, unseen applications and timestamped
  absence, wishlist and recipe events do not exist yet.

---

## ADR-0017 — Beta builds ship as GitHub pre-releases, outside the stores

> **Superseded in part by ADR-0021.** The stores added the flavour, so the committed TOC now carries Forever's
> interface and `publish.yml` names no flavour. What stays: a `-beta.N` tag is a GitHub pre-release and nothing
> else. What goes: the stamp that added the interfaces, and the reason for it.

### Context
WoW: Forever's beta opens before CurseForge, Wago or WoWInterface know the flavour, and the BigWigs packager labels
an interface it does not know as retail. Adding Forever's interface to the committed TOC and publishing through
`publish.yml` (`-g bcc`) risks mislabelling the Anniversary release. Testers still need one zip on day one.

### Decision
- A `vX.Y.Z-beta.N` tag triggers `.github/workflows/beta.yml`, and nothing else does.
- In its own checkout the job appends `16000, 16001` (Forever's 1.60.x build line by the `%d%02d%02d` rule) to the
  committed Anniversary interface, which stays first (today `## Interface: 20506, 16000, 16001`), and stamps the
  tag's version into the TOC and `GuildOS.VERSION`.
- It packages with the BigWigs packager in `-d` mode (no upload) and attaches the zip to a GitHub pre-release.
- `release.yml` (runs on `main`, reads only `vX.Y.Z` tags) and `publish.yml` (runs only when dispatched: by `release.yml`, or by hand) are
  unchanged, and so is the committed TOC.

### Consequences
- (+) Testers get a loadable build without touching the stores' flavour detection.
- (+) `/guildos probe` records the beta version, so a returned SavedVariables file says which build produced it.
- (−) The interface list is a guess until the beta shows its number; until then Forever may need "Load out of date
  AddOns".
- (−) How the packager treats a TOC listing interfaces it does not know is proven only by the first beta tag.

---

## ADR-0018 — A member key without a realm is the name alone

### Context
Every member key is "Name-Realm". WoW: Forever has no realms, and `GetRealmName()` there may return nil or "". The
key rule raised on a nil realm, several places built keys by hand and raised too, and LootMaster and the wishlist fell
back to "" in some places and "Unknown" in others, which split one member across keys that never meet.

### Decision
- `BRutus:GetPlayerKey(name, realm)` is the only rule. An empty realm counts as absent and falls back to the
  client's realm (`BRutus:GetClientRealm()`): `GetRealmName()`, else `GetNormalizedRealmName()`; an empty answer
  counts as absent too.
- With a realm the key stays `name .. "-" .. realm`. Without one it is the name alone, not "Name-".
- Every hand-built member key goes through the rule. PugInspector's pure classifier applies it inline.
- `GetRealmName` first, so Anniversary keys keep their bytes for realms with spaces or apostrophes; the normalized
  name only when it answers nothing. A received broadcast with no realm takes the client's, as in 0.53.0; only a
  client with no realm at all takes the sender's own suffix.

### Consequences
- (+) Anniversary keys, SavedVariables and sync payloads are byte-identical; nothing migrates.
- (+) On a realm-less client nothing raises, and each member has one key that splits and rejoins to itself.
- (−) A hyphenated realm-less name ("Anne-Marie") still reads as name plus realm wherever a site only looks at the
  short name; that waits for the beta to show whether such names exist.
- (−) Slash commands that take one word still cannot name a two-part character.
- (−) On a client whose roster suffixes names while both realm functions answer nothing, keys split: roster rows and
  suffixed senders carry the suffix, while keys built from a bare name (my own, loot, rolls, commands, attendance,
  member records) do not, and my own messages come back as a second record. `/guildos probe` records both realm
  functions and the first roster name, so the beta shows whether that state exists.

---

## ADR-0019 — Version-sensitive calls go through Compat, and sync and loot sends act on their result

### Context
The loop that matters on WoW: Forever's first day (the roster, your own character, sync with the other officers) called
item, spell, aura, bag, talent and skill-line APIs directly. One missing talent or skill-line function stopped
collection, and with it the broadcast and the companion export. Addon sends ignored their result, so a chat lockdown
dropped sync without a trace. Two shims in `Core/Compat.lua` had no callers.

### Decision
- Those calls go through `Core/Compat.lua`: the namespaced API (`C_Item`, `C_Spell`, `C_UnitAuras`, `C_Container`,
  `C_GuildInfo`, `C_ChatInfo`) first, then the old global, else nothing. Talent and skill-line counts say `"no-api"`.
- Collection leaves `spec` and `professions` absent when their API is missing and names them in an `absent` marker the
  other officers apply; the export follows, while a published empty list and a row that never published keep
  `professions: []` as before.
- Guild sync (`CommSystem`) sends through `Compat.SendAddonMessage`, with ChatThrottleLib underneath; loot messages
  (`LootMaster`) through `Compat.SendAddonMessageNow`, at once as before. Both act on the result: a lockdown holds the
  message (flushed in order on combat end, a zone change or a 2-second poll, 200 at most), a channel throttle (and, on the loot path, an addon-message throttle) retries
  four times with backoff, and any other failure, or a message the client would refuse, is recorded once. Result codes
  are read from `Enum.SendAddonMessageResult` by name. LibChehulMesh (AceComm) and the probe's single test message keep
  their own paths.
- `tools/compat-guard.lua` runs in CI and fails when these APIs are reached outside Compat by name: a call, an existence
  check, a concatenation, a field off `_G` or a sender's namespace, a quoted string index on a plain name on the same
  line, an alias of a namespace or `_G`, a single-name `Compat` alias, or `getfenv` (Probe and ChehulNet exempt). It
  reads names, not expressions: a name built at run time, a parenthesised or chained receiver and a compound `Compat`
  assignment are not followed. `Compat.NewTimer` is removed; `RegisterAddonPrefix` and `SendAddonMessage` are wired in.

### Consequences
- (+) A missing API on a new client costs one field instead of collection and sync, and the other officers follow.
- (+) A lockdown or a throttle no longer loses sync silently; anything else shows in `/guildos errors`.
- (+) Anniversary payloads, the companion export and loot timing are unchanged, and CI keeps new direct calls out.
- (−) A lockdown that splits a chunked message can let the receiver's 30-second reassembly expire; the next broadcast
  repairs it.
- (−) Forever's result names are unconfirmed until `/guildos probe` runs on the beta; the fallbacks are the retail codes.

## ADR-0020 — The retail tooltip: one registration per data type, filtered to the tooltips that asked

### Context
On the WoW: Forever beta the addon opened with four start-up problems: `event CRAFT_SHOW` and the three
`OnTooltipSetItem/Spell/Unit` scripts. Forever runs the retail tooltip, which has neither those scripts nor
`tooltip:GetItem()`; it has `TooltipDataProcessor.AddTooltipPostCall(dataType, fn)` and
`TooltipUtil.GetDisplayedItem/Spell/Unit(tooltip)`. `CRAFT_SHOW` belongs to a craft window this client never had.
`Compat.HookTooltip` recorded all four and moved on, so nothing raised — but SoftRes reserves, wishlist marks, the
recipe crafters and the ban flag were all silently absent, and the fourth line was noise.

### Decision
- `Compat.HookTooltip` asks the frame first: where the script exists (Anniversary) it is a `HookScript`, as before.
  Where it does not but the client has the processor, the same function is registered **once** per script — the
  registration is global, one per data type, so registering per tooltip would add its lines once per tooltip.
- What is registered is a wrapper, not the caller's function: it answers only for the tooltips that asked for it and
  never for a forbidden one. A hook on GameTooltip alone stays a hook on GameTooltip alone, on both clients.
- The callback receives `(tooltip, data)`, the tooltip first, the way the script did.
- `Compat.TooltipItem/TooltipSpell/TooltipUnit` read what is under the mouse, asking the frame first — the same
  question the hook asked, so on a client with both the reading matches the hook — and falling through to
  `TooltipUtil`. The first two returns are the same on both; the retail client adds a third.
- `Compat.RegisterEvent(frame, event, expected)`: `expected` is an event only some clients ever had. It still
  registers where it exists, and where it does not it is recorded once and left out of `ListStartupProblems`. A later
  miss of the same name without `expected` still wins and becomes an error. `CRAFT_SHOW` is the only caller.
- `tools/compat-guard.lua` covers `TooltipUtil`, `TooltipDataProcessor`, `Enum.TooltipDataType` and the `GetItem`,
  `GetSpell`, `GetUnit` methods, so CI keeps them inside Compat. Every harness now runs in CI as well.

### Consequences
- (+) Reserves, wishlist, crafters and the ban flag work on Forever, and the beta's start-up list is quiet.
- (+) Anniversary takes the same path as always: the frame's script, and the frame's own readers.
- (+) The ban flag stopped reading `UnitName` raw, which would have raised on a unit whose identity is secret — the
  bug was dormant only because the hook never landed there.
- (−) The dedupe is keyed on the function itself, so a module that hooks twice with two closures registers twice.
  `InitModules` runs once per session; a future re-init would double the lines with nothing to catch it.
- (−) A client with the processor but without `TooltipUtil` hooks and reads nothing. `/guildos probe` asks for both.

---

## ADR-0021 — One build for both clients, and the store decides from the TOC

### Context
ADR-0017 kept Forever's interface out of the committed TOC because no store knew the flavour and the packager
called an unknown interface retail. Both have changed: CurseForge lists **Forever** (`gameVersionTypeId=88568`),
Wago's registry carries `forever: 1.60.1`, and the packager maps `16???` to `forever` (alias `camelot`, TOC suffix
`_Camelot`) from commit `e50a250f` on. GuildOS was publishing to TBC only, with `-g bcc`.

### Decision
- `GuildOS.toc` carries `## Interface: 20506, 16001` — Anniversary first, so it shows no out-of-date warning
  there. One file, two clients; no `_Camelot.toc`, which the beta showed is not needed.
- `publish.yml` names **no** flavour. The versions come from that interface line, so one upload is marked for
  both (`Game version: 2.5.6, 1.60.1`). A flavour named there publishes to that one and drops the other.
- Both workflows pin the packager by commit, not by the `v2` tag: `publish.yml` runs third-party code with the
  store keys.
- `beta.yml` stops stamping interfaces and instead **refuses to build** a TOC that lost Forever's, which is the
  one thing about that zip nothing else would notice.

### Consequences
- (+) The beta client installs GuildOS from the store like any other addon, and a release reaches both at once.
- (+) The version the store shows follows the TOC, so a client patch bump is one line in one place.
- (−) The zip and the store's display name lose the `-bcc` suffix: the file is no longer one flavour's.
- (−) **A version the store stops listing does not fail the publish.** The packager falls back to the nearest
  version of that flavour, else drops it with a warning, and the job still goes green — so the publish log is the
  only place that says Forever was tagged. Read `Game version:` and `ignoring` there.
- (−) 16001 is read from the client's crash reports and the rule, not from `GetBuildInfo` on a running client.
  Wrong, it costs an out-of-date warning in game, not a failed upload.
