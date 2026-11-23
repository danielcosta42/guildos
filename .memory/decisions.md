# GuildOS — Architectural Decision Records

_Last updated: 2026-04-26_

Architectural Decision Records (ADRs) for GuildOS.
This is the canonical record of WHY the codebase is structured as it is.
Add a new ADR whenever you introduce a significant architectural pattern or change.

---

## ADR-0001 — Single `GuildOS` global namespace

### Context
WoW addons share a global environment. Name collisions between addons are a real hazard.
Classic TBC clients do not support modern Lua module systems or table-passing via `...`.

### Decision
Create exactly one global: `GuildOS`. All modules attach as sub-tables (`GuildOS.CommSystem`, `GuildOS.UI`, etc.).
`Core.lua` is the only file that creates the global; all other files assume it exists.

### Consequences
- (+) One global to audit; no accidental global leakage.
- (+) Compatible with all WoW Classic client versions.
- (+) Sub-modules can alias locally: `local RT = GuildOS.RaidTracker`.
- (−) Modules must be loaded in the correct order. Enforced by `.toc`.

---

## ADR-0002 — Per-guild SavedVariables key

### Context
A single GuildOS installation may be used on multiple guilds (server transfers, alts in different guilds).
Mixing guild data in a single flat DB would contaminate one guild's data with another's.

### Decision
`GuildOSDB` uses a `"GuildName-Realm"` key as the top-level partition.
`GuildOS:ResolveGuildDB()` creates or retrieves the guild-specific sub-table and stores it as `GuildOS.db`.
All modules read/write `GuildOS.db`, never `GuildOSDB` directly.

### Consequences
- (+) Complete data isolation per guild per realm.
- (+) Migrations only need to handle one sub-table at a time.
- (−) If a player changes guilds, old guild data remains in `GuildOSDB` until cleared manually.

---

## ADR-0003 — Cross-version compatibility layer (`GuildOS.Compat`)

### Context
TBC Anniversary uses a different API surface than progressive Classic or Retail.
`C_ChatInfo`, `C_QuestLog`, `C_GuildInfo`, and `C_Timer` may or may not be present.
Inline version checks scattered across modules would become unmanageable.

### Decision
All version-sensitive API calls go through `GuildOS.Compat` wrappers (defined in `Core.lua`).
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
`GuildOS.State.comm.pendingMessages` holds in-flight chunk sets.

### Consequences
- (+) Can send any size payload safely.
- (+) ChatThrottleLib prevents server-side throttle kicks.
- (−) Adds 3 library dependencies (LibSerialize, LibDeflate, ChatThrottleLib).
- (−) Small messages still go through the full pipeline (acceptable overhead).

---

## ADR-0005 — Session state in `GuildOS.State` (not as module member vars)

### Context
Early versions stored session state as module-level member vars (e.g. `LootMaster.activeLoot`,
`CommSystem.lastBroadcast`). These are reset on `/reload` anyway but pollute the module table
with non-persistent data, making it unclear what is saved and what is runtime-only.

### Decision
All runtime-only, non-persistent data lives in `GuildOS.State` (a table created in `Core.lua`).
Sub-tables mirror module ownership: `GuildOS.State.comm`, `GuildOS.State.lootMaster`, etc.
Module tables only contain methods and constants.

### Consequences
- (+) Clear boundary: `GuildOS.db.*` = persisted, `GuildOS.State.*` = runtime-only.
- (+) Easier to inspect/reset session state in one place.
- (+) Module tables are cleaner (methods only).
- (−) Slightly more verbose access path: `GuildOS.State.lootMaster.activeLoot`.

---

## ADR-0006 — No centralized event pub/sub (yet)

### Context
AutoRaidCoach uses a centralized `Events.lua` pub/sub system where all game events route
through a single frame and modules subscribe with `On(eventName, fn)`.
GuildOS predates this pattern and has event frames scattered across modules.

### Decision
GuildOS does NOT yet have a centralized event system.
Each module creates its own event frame inside `Initialize()` for the events it needs.
The `GuildOS` frame in `Core.lua` handles core events (PLAYER_LOGIN, GUILD_ROSTER_UPDATE, etc.).

**Future direction**: Extract to a centralized `Events.lua` when the module count grows enough
to justify the refactor. An ADR will be added at that point.

### Consequences
- (+) Simpler to reason about per-module event scope.
- (+) No risk of one module's handler affecting another.
- (−) Multiple frames registered for the same event (minor overhead).
- (−) No built-in decoupling between event source and handlers.

---

## ADR-0007 — Config accessors (`GuildOS:GetSetting` / `GuildOS:SetSetting`)

### Context
UI callbacks were directly reading/writing `GuildOS.db.settings.*`. This tightly couples UI files
to the internal SavedVariables structure and makes future schema migrations harder.

### Decision
All reads and writes of `GuildOS.db.settings.*` go through:
```lua
GuildOS:GetSetting(key)        -- reads GuildOS.db.settings[key]
GuildOS:SetSetting(key, value) -- writes GuildOS.db.settings[key]
```
UI files must use these accessors. Only `Core.lua` accesses `GuildOS.db.settings` directly
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
`GuildOS._origToggleGuildFrame` (captured in `Core:HookGuildFrame`). The
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

## ADR-0011 — Localization (`GuildOS.L`, English-key, metatable fallback)

### Context
The addon was originally Brazilian Portuguese with strings hardcoded and mixed
PT/EN throughout. To serve a general (international) audience it needed full i18n
with English as the default and additional languages.

### Decision
Add a lightweight localization layer (no Ace/LibStub dependency):
- `Locales/Locale.lua` creates `GuildOS.L = setmetatable({}, { __index = function(_, k) return k end })`.
  Keys are the **canonical English strings used directly in source** (`L["Roster"]`),
  so a missing translation falls back to readable English (never nil, no symbolic
  key leakage). `GuildOS.Locale = GetLocale()`.
- Loaded **right after `Config.lua`** (before any file that aliases `local L = GuildOS.L`).
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
`GuildOS:InitModules` called ~50 `Initialize()` functions in sequence with no isolation, so one
missing API made one module raise and left every later module unstarted. `RegisterEvent` on an
event the client does not know and `HookScript` on a tooltip script the frame lacks raise too.

### Decision
- Start-up is a list (`MODULE_START`, `OFFICER_START` in `Core.lua`) run through
  `GuildOS:RunStartup`, which `xpcall`s each step (keeping the stack) and records the failure against the module and
  the feature/window it backs. Failed windows refuse to open with a message.
- Events are registered through `GuildOS.Compat.RegisterEvent`, tooltip scripts hooked through
  `GuildOS.Compat.HookTooltip`; a miss is recorded once in `State.missing`.
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
nor WoW: Forever. About 2,000 call sites read `GuildOS.Colors`, and 242 `SetFont` calls used
`Fonts\\FRIZQT__.TTF`.

### Decision
- `GuildOS.Colors` carries the 17 tokens from the design handoff. The legacy keys the screens read
  stay, each a copy of the token that plays its role, so the whole UI re-skins without touching its
  call sites. Gold is the only accent and the only colour allowed as a background; violet only means
  epic quality. The accent picker (`ACCENT_PRESETS`, `ApplyTheme`) is removed.
- Four OFL fonts ship in `Media/Fonts`. Every font goes through `GuildOS:ApplyFont`, which enforces
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
- `GuildOS.Client` in `Core/Compat.lua`, computed once at load: the `GetBuildInfo` fields, `projectId` for
  diagnostics, `isAnniversary` and the `has` capability flags (`secrets`, `chatLockdown`, `tradeSkillUI`,
  `tooltipData`, `guildSetNote`).
- `isAnniversary` needs both `WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC` and an interface in
  20500–29999. Everything else, an unknown client included, is "not Anniversary". There is no flavour field.
- TBC content is absent outside Anniversary rather than disabled: `AttunementTracker.lua` and
  `ConsumableChecker.lua` return before defining their global, so every existing `if GuildOS.X then` guard
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

**Amendment (ADR-0026).** Retail is the third client, recognised the same way: `WOW_PROJECT_ID ==
WOW_PROJECT_MAINLINE` and an interface of 100000 or more (`GuildOS.Client.isRetail`). An unknown client is still
Forever. `GuildOS.Client.game` names the client for the payload and diagnostics; nothing else branches on it.

**Amendment (issue #187).** `ConsumableChecker.lua` exists on retail too, with Midnight's table: it returns early only
on WoW: Forever, and its feature carries `forever = false` (`UI:IsFeatureAbsent`) instead of `tbc = true`.

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
- One window, `GuildOS.RosterFrame` (frame `GuildOSWindow`), built in `UI/Window.lua`. Every registry feature
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
- `GuildOS:GetPlayerKey(name, realm)` is the only rule. An empty realm counts as absent and falls back to the
  client's realm (`GuildOS:GetClientRealm()`): `GetRealmName()`, else `GetNormalizedRealmName()`; an empty answer
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


**Amendment (issue #95).** On WoW: Forever the realm a caller passes is ignored and the client's own is used: Forever has no realms that set players apart, yet a guild's clients answer different `GetRealmName()` values (the beta's "Classic Beta PvE" and "Classic Beta PvE 2"), and a broadcast keyed with its sender's realm never met the receiver's roster line. Keys still agree only within a client: a key built by another client and carried inside a payload must be localized on receipt.

**Amendment (issue #97).** It is: `GuildOS:LocalMemberKey` rebuilds a carried key from its name (Forever names hold no hyphen, so the name is what comes before the first one), and every receive path that takes a member key out of a payload goes through it, while the sign-up is filed under its envelope's sender rather than any key the payload names. Two of the sender's keys that turn out to be one member are settled by that table's own merge, which only ever sees two records; a value that is not a record never replaces one. What an earlier version stored that way is rekeyed by `LocalizeStoredMemberTables` once per database, each table under its own `SafeCall` so bad stored data in one neither stops start-up nor leaves the others behind. The alliance bridge hashes the name alone on Forever, so clients on different realms elect the same one. Anniversary keys pass through untouched: there a realm is part of who somebody is.

**Amendment (ADR-0026).** None of the Forever rule holds on retail: a realm is part of who somebody is there, as on
Anniversary, and a guild spans connected realms. `GuildOS:RealmBound()` (Anniversary or retail) is the one test:
`GetPlayerKey` keeps the caller's realm, `LocalMemberKey` passes a key through, and neither start-up rekey runs. Retail
spells every realm normalized, without spaces or hyphens, the way its roster and senders write it, so a realm taken
from `GetRealmName()` or a unit meets the roster's.

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

**Amendment (ADR-0026).** The interface line carries retail's too: `## Interface: 20506, 16001, 120105`, added last
so no half-made release reached the Retail flavour. `beta.yml` still refuses a TOC without 16001 and accepts more
interfaces after it. A retail patch bumps the third number.

---

## ADR-0022 — Professions on Forever by ID: passive IsPlayerSpell over a generated catalog, hash-summarized sync

### Context
On WoW: Forever the Classic profession API is gone, so GuildOS collected nothing: no levels, no recipes, and every
surface that reads them was empty. A throwaway probe in the beta (2026-09-27) showed that `GetProfessionInfo`
gives exact ranks with the window closed, that `IsPlayerSpell(recipeID)` matches the window's learned list
exactly (while `C_SpellBook.IsSpellInSpellBook` does not), and that the Communities roster names every member's
primary professions, addon or not, with no rank. Professions are expected to be central in Forever (epic #30).

### Decision
- Key professions by skill-line ID and recipes by recipe ID, never by name.
- Ship a static catalog generated from the build's DB2 (`tools/prof_catalog.py`) and learn recipes by asking
  `IsPlayerSpell` for each recipe of each owned line: no window, no reminder. The own window only adds recipes
  the catalog lacks (`extra`), which bridges a beta build newer than the catalog.
- Sync through a `prof` SyncService domain: a small summary with a hash per profession on login, on change and
  every 10 min; a list only when a hash changes, answered once per burst (whisper, or GUILD for several).
  The member broadcast stops carrying recipes on Forever.
- Members without the addon come from the Communities roster, as a native record an addon record replaces.
- An adapter projects the model into the legacy shapes, so every existing surface works unchanged.
- Forever only. Anniversary keeps its path untouched.

### Consequences
- (+) Every member's professions and recipes, with nobody opening a window; lists travel once per change.
- (+) Members without the addon still show their professions.
- (+) The catalog (outputs, reagents, stations, specializations) is the base the directory, coverage and site
  sub-projects build on.
- (−) The catalog must be regenerated per beta build; `/guildos probe` reports the catalog build and how many
  extra recipes the client found, the signal to regenerate.
- (−) Recipe required skill for trainer recipes is not in the client data.
- (−) Names in `db.recipes` are the reader's client's language, as before.

**Amendment (ADR-0026).** Retail has its own catalog, `Data/ProfCatalogRetail.lua` (`tools/prof_catalog.py
--retail <build>`), with only the current expansion's recipes: they sit on the parent line, and a row's
`SkillupSkillLineID` names the expansion line it levels. The output comes from `CraftingData` (or its first quality
tier), enchants from Effect 301; tiered reagents are left out. Forever's catalog loads on Forever only. Regenerate the
retail one on every retail patch.

---

## ADR-0023 — A raid's core comes from its roster; the active core is the fallback

### Context
The active core (`RaidTracker.currentGroupTag`) is per client and set by hand, and it decides which core a raid's
session, DKP pool and loot rules belong to. A guild on WoW: Forever plans 8 to 12 rosters of 20 (issue #99): an
officer leading several had to switch before every raid, and forgetting sent the night to the wrong core silently.

### Decision
- Each snapshot inside the raid matches the group (that snapshot's members, never everyone the session has seen)
  against each core's roster, an alt counting as their main (`CoreManager:CoreForGroup`).
- A core can take the raid when at least two people and at least half the group are on its roster. A raider may
  be on several cores, one per format (issue #132), so a guild's 40 holds its 10's people: of those cores, one
  whose raid size holds the raid comes first, then the smaller format, then the one with more of the group, and
  two that rank the same take nothing. The raid's size is the instance's (the session's `size`, ADR-0024) when
  that is one of the game's formats, else the group's own size, so a raid in a 20's instance is the 20 core's
  while it fills, and a flexible size no core plans for falls back to counting heads. It becomes the active core and the session's, and a chat line names it
  the first time and whenever it changes.
- Until the first boss is pulled the raid follows the group, so one still being invited ends on the roster that
  showed up; `encounter_start` settles it. Detection never runs once the raid is left: not in the 20-minute
  grace period and not on the session's last snapshot.
- An officer's pick (Raid Core's "Set Active", `RaidTracker:PickCore`) inside the raid is final for it. It is
  kept for that character and instance while the raid goes on (each snapshot refreshes it; it lapses 30 minutes
  after the last), so a /reload or a disconnect keeps it, and it ends with its session: a later raid, an alt or
  another instance is asked afresh. A pick on a wipe's run-back (the grace period) is the raid's once it resumes;
  outside any raid it is only what the next raid falls back to, and drops a kept one. A rename carries the raid,
  the kept pick and the announced core along. A pick applied without a click right then (kept, or from the
  run-back) is named in chat, so no pick takes a raid silently.
- A /reload or a login inside a raid fires no zone change, so `PLAYER_ENTERING_WORLD` runs `CheckZone` once:
  the session (attendance with it) picks back up at once instead of at the next wipe, and finds a kept pick
  while it is fresh.
- Any change of active core re-reads the loot rules cached from the core's config.
- Nothing matches, a tie, or no rosters: the active core stands, silently, as before.

### Consequences
- (+) Every core is usable at once; the night goes to the roster that showed up.
- (+) An officer's pick still wins, and fixes a wrong guess mid-raid.
- (−) A raid formed mostly of pugs, or split evenly between two rosters, falls back to the hand-set core.
- (−) Detection is local, like the active core: every officer tracking the raid works it out on their own client.
- (−) Awards made before the first pull go to the core the raid was on at that moment.
- (−) A guess made while the group formed stays when the formed raid matches no roster, rather than going back
  to the hand-set core; the chat line names it, and "Set Active" fixes it.
- (?) On WoW: Forever nobody has read whether `UnitName("raidN")` gives the whole name; if it gives the first name
  only, raid keys miss every roster (attendance as much as detection). Verify when raids open.

---

## ADR-0024 — On WoW: Forever every raid is tracked, and progression is the size the game gives

### Context
Progression attendance (the "25-man" figures: `raids25`, the score, the percentage every screen and the loot
tiebreaker read) counted TBC's 25-player raids by instance id, and RaidTracker only tracked the raids it listed.
WoW: Forever's raids open on 9 December 2026 with ids nobody has: on Forever no raid was recorded at all, and
the screens said "25-man". Each Forever tier is a 10-player raid and a 20-player one; Onyxia at 40 was said in
a Q&A (issue #90).

### Decision (the owner's, 2026-10-05)
- On Forever every instance of type "raid" is tracked, named by the game (`GetInstanceInfo`).
- A session keeps `size`, the game's maxPlayers on the way in. On Forever a night counts for progression when
  its size is 20 or more: the 20s and the 40, never the 10s, as Karazhan never counted on TBC.
- The size travels with the officers' raid sync and with the companion payload (v9); merging two halves of a
  night keeps it.
- On Forever the "25-man" labels read "20+" (`RaidTracker:ProgLabel`, on the translated text).
- Anniversary is unchanged: tracked and counted by its lists of ids.

### Consequences
- (+) The raids of 9 December, and every tier after, are tracked and counted with no release.
- (−) A night recorded before sizes were kept has none, and on Forever does not count; there were none.
- (−) The site must count the same way from the size, or its attendance disagrees with the game's.
- (?) Verify on 9 December: that `maxPlayers` is the raid's designed size (a flexible difficulty on a retail
  engine reports 30, and would count a 10), and that a 10 and a 20 are different instance ids (lockouts are keyed
  by id and week; one id hosting both would credit a 10's raiders). "Raid tracking started" names the size on
  Forever so it shows on day one.
- (−) The pug-night mark (`isGuildRaid = false`) now travels with the officers' raid sync on both games, and
  fills in a copy that lacks it: a pug night stops counting on every officer's client and, through their
  uploads, on the site, past nights included, as it always did on the officer who recorded it. That changes
  Anniversary numbers where a pug night had spread without its mark.
- (−) A Forever session's name is the client's language and Forever has no `RAID_KEYS`, so no `raidId` is
  stamped and the site matches it to a planned raid by name: a translated name can miss (site issue).

---

## ADR-0025 — The Discord owns who is on a core; the addon imports and never touches an officer's own

### Context
A core lives on the Discord (the bot's federation, guildos-web spec 035) and in the game. Since #132 both let a
person be on several cores, but nothing joined them: an officer accepting somebody on the Discord added them by
hand in the game too (issue #135, guildos-web specs/041).

### Decision
- One way only, site to game. The site sends a guild's cores as a `GOSCORE1` (the GOSROST1 codec) in a field of
  its own on `/api/roster`; the companion writes it into `Inbox.lua` after the raid rosters.
- `CoreManager:ImportInbox` runs from `CoreManager:Initialize`, once the guild's db is known (PLAYER_LOGIN does
  not wait for it), and only with the companion on, the payload's `guild` this guild (capitals aside, #144: it is the site's spelling) and, on Anniversary, its
  `realm` this realm (one Inbox.lua serves every realm of an install).
- The game's core is the one already linked to the Discord core's tag; else the one whose name `CoreManager.Slug`
  (the site's `slugOf`) reduces to the tag, the one named as on the Discord when two do; else one made then, under the Discord's name, or the tag
  when the name does not reduce to it. Its `raidSize` is the Discord's.
- A member the Discord sends and the core lacks joins, marked `src = "discord"`. One already there, put by an
  officer, becomes the Discord's (#138): class, role and note as the officer left them, the tag shown, and it
  leaves with the Discord. A `src = "discord"` member the Discord no longer sends goes. `AddMember` keeps the
  `src` it had, so an officer's edit does not change who owns the record. Whoever the Discord does not have
  is never touched. One function does it, `SyncDiscordCore`, for the import and for another officer's list.
- The other officers get, at every import, the Discord's whole list for each of its cores (#138): `core.roster`
  with action `discordList` (`list` as the site sent it, `size`, `tag`, `waiting`, `at`), reconciled there by the
  same `SyncDiscordCore`, so a client that missed a login, or deleted the core, converges. Never the officers'
  own roster, which would write over a pug another officer added while this client was away. The action is new
  and the field is `list`, never `members`: a client from before #135 takes any `members` for the whole roster,
  and 0.73.0 would take a `discord` message for a change with nothing in it, linking an empty core under the
  sender's name; both ignore `discordList`. It is sent from OFFICER_START (`SendDiscordChanges`), once the guild
  rank is known (it is not at login, #79). Releases keep action `discord` (`tag = false`), which 0.73.0 applies.
  The change alone that 0.73.0 sends (`add`, `remove`) is still applied, by `ApplyDiscordChanges`, to the core
  holding the tag here whatever the sender calls it, while this client has no list it can date.
- A list from another officer lands on the core holding its tag here, picked as the import picks it: a list
  never moves a tag. Only a link does: every list of a core linked by hand carries when it was linked
  (`linkAt`, the realm's clock), and a client whose core for that tag was linked earlier, or never, moves the
  tag to the sender's core, unless that core is another Discord core's there. A link is an officer's choice,
  not the Discord's data: it is never judged by how new the lists it came with are, except to link a tag no
  core holds on the receiver (closed on the Discord since, maybe). A link is undone by linking another core;
  a core linked by hand and deleted comes back with the next list that carries its link.
- `at` is the package's own: when the guild's cores last changed, on the site's clock (guildos-web #126); from a
  site before it, when the companion wrote the inbox (`GuildOSInboxAck.at`). From the first package the site
  dates (`db.discordSiteAt`), a PC's clock no longer counts: the mark it left is dropped, and an inbox the site
  did not date is from before and is skipped. The site sends every core of the guild together, so
  the guild keeps one mark, the newest `at` it applied from its inbox or from another officer
  (`GuildOS.db.discordAt`), releases included. An inbox, a list or a release older than it is skipped, and an
  inbox skipped is not sent on: an officer whose companion stopped rolls nobody back, and an older inbox never
  gives back a core the Discord still has, nor links again one the Discord closed. An `at` past the realm's
  clock counts as now; another officer's message with none, once the guild has a mark, as older.
- One tag, one core. A core taking a tag another core holds takes the Discord's people with it (`release` with
  `moved`); left behind, they would be the same people on two cores, a tie no raid detection can settle.
- An import that ignored the inbox says why, once per guild until the reason changes (#138): cores of another
  guild (checked first: an alt elsewhere is not told to switch anything on), or the companion off in game. Who is on a Discord core with no confirmed character is kept on the core
  (`discordWaiting`, the site's `waiting`) and shown in its Roster tab.
- A game core named apart from its Discord core is linked by hand (#138): Config, "Discord core", from the
  cores the last import saw (`DiscordCatalog`). `LinkDiscord` moves the tag and the Discord's people, as they
  are, from the core that held it, stamps `linkAt` and sends its list, so the other officers hear the link
  now; it needs no inbox (only when no core holds the tag does it import again, and links nothing when it
  cannot). A core already another Discord core's is not linked. A core linked by hand is never
  taken by another Discord core of its name; one made for a Discord core never takes a name already used.
  Deleting the active core clears it, in the raid too (the raid's core, the announced one, an officer's pick),
  so the next read does not make it again, empty.
- One chat line says what changed and how many people the site had no character for (each once).
- A core the import links keeps the Discord's tag (`discordTag`, sent with the change as `tag`). While it does, the
  core panel offers neither Rename (a renamed core stops being the Discord's and the import makes it again) nor the
  raid format (the Discord's comes back), nor the "x" on a member the Discord put there; the role stays the
  officers'. Delete stays: the way out, undone by the import while the Discord still has the core. A core the
  Discord no longer sends (closed there, or the federation off: the site then sends an empty package) is given
  back to the officers, as it stands, and the release goes to the other officers too (`tag = false`), never
  making again a core one of them deleted. A second core carrying a tag another core has is given back as well.

### Consequences
- (+) Joining or leaving a core on the Discord reaches the game without an officer retyping it.
- (+) Pugs and people with no character on the site stay on the cores an officer put them on.
- (−) Taken off only in the game, a Discord member is back at the next import: the Discord is where they leave.
- (−) It arrives at the login or /reload of whoever runs the companion; an officer offline when that client
  sends keeps the old roster until the next send, and the Discord's `raidSize` reaches only importing clients.
- (−) Only people with a confirmed character on the site come through; the rest are a count.
- (−) An officer on a version before #135 who edits a Discord member rebuilds the record without `src`: from then
  on it is that officer's, and leaving the Discord no longer takes it off.
- (−) Once a client has a list it can date, a 0.73.0 officer's change (it carries no time) is skipped there.
- (−) Who waits for a character goes to every client of the guild with the lists, by Discord display name: the
  names the guild's own Discord server already shows them.

---

## ADR-0026 — Retail, the third client: absent where it does not apply, realm-bound keys

### Context
To reach more players, GuildOS runs on retail (Midnight, 12.1.5, interface 120105) as well as WoW: Forever. Retail
used to fall into "not Anniversary", which is Forever: a level cap of 60, the realm read as a surname, the Forever
profession catalog, a payload marked FOREVER and, worst, a start-up rekey that merged members of different connected
realms into one record. Retail's documented API is the same as Forever's (both builds' API documentation compared,
2026-10-17), so the work is identity and content, not calls. Retail is personal loot only, and guildos.me takes no
retail guild yet.

### Decision
- `GuildOS.Client.isRetail` (ADR-0014's two signals) and per-game fields: `maxLevel` 90, `raidSizes` 10/20/30,
  `classes` (thirteen), `enchantSlots` (Midnight's head, shoulder, chest, legs, feet, rings and both weapons; an
  off hand only when it is a weapon, `GearAudit:NeedsEnchant`; issue #177).
- Keys are realm-bound on retail, normalized (amendment to ADR-0018). Everything that names a guildmate keeps
  their realm: the core's member picker (`GuildOS:KeyOfRosterName`), poll votes and calendar answers, the roster
  lookup. Officer trust is the whole key: an officer's name on another connected realm carries no rank
  (`IsOfficerByName`). The guild's database is keyed on the guild's home realm (`GetGuildInfo`'s fourth answer,
  normalized), so one guild is one database whichever of its realms a character is on.
- The roster rail lays its class chips out with `UI:ChipGrid`: three columns for retail's thirteen, still five rows.
- Absent on retail, as TBC content is elsewhere: LootMaster, LootTracker, LootEquity, Points, SoftRes, Wishlist,
  CompanionExport, CompanionImport, Look and Resistances (no resistance gear; its scan, sync and `/gos resscan`
  follow it, issue #184) return before defining their globals. Features carry `retail = false`
  (loot, dkp, wishlist, web, lootTracker, lootMaster); the Settings loot category, the core's loot rules, the loot
  quick buttons and tests, the loot export datasets, the dashboard's loot card and the site link follow the modules.
  A slash verb of an absent module says "Not available on this client." The player's toggles are untouched.
- Retail content: specs from `C_SpecializationInfo` (`Compat.SpecOf`), raids tracked by difficulty (Normal, Heroic,
  Mythic; every one progression), the item level as worn (`Compat.ItemLevel`) and the game's average, Raid Tools'
  Midnight buffs and cooldowns named by the client from the spell, the Midnight profession catalog (ADR-0022).
- A boss name the client keeps secret is never concatenated or stored, on every client; nor is a difficulty name.
- A spec synced from a guildmate shows in the reader's language, by its id (`SpecChecker:SpecName`). A session keeps
  its difficulty, shows it ("N", "H", "M"), sends it in the raid sync, and a raid's Normal and Heroic are never
  merged into one session. A tab or an export this client does not have says "Not available on this client."
  (`UI:IsFeatureAbsent`, `Exporter:Has`) (issue #177).
- What #184 filled in: the core's raid buffs are Raid Tools' Midnight list (one table); a scanned spec sets the
  role a member starts in (`CoreManager:DefaultRole`, melee or ranged by `MELEE_SPECS` from ChrSpecialization's
  flags); a group scan brings a guildmate's item level (`Compat.InspectItemLevel`) without overwriting a newer
  broadcast of theirs; the member sheet shows the primary stat, stamina and the four ratings
  (`Compat.PrimaryStat`, `Compat.SecondaryStats`); my spec change goes out at once
  (`PLAYER_SPECIALIZATION_CHANGED`); the alliance roster carries the spec id; recruitment knows the Italian
  client's channels; a raid roster name the client keeps secret is skipped.
- Namesakes on connected realms are told apart by the whole key (issue #184): BanList files a ban under it; a
  name without a realm is this realm's, never a guess at a namesake elsewhere, so every caller hands over the
  whole name it has (the whisper's author, the popup's queued name, /who's fullName). A ban filed under the
  name alone before still holds on every realm, also after the whole key's own ban is lifted. The ban list
  lifts the row it shows by that row's key (`List` carries it, `RemoveKey`); `/gos unban Name-Realm` lifts
  that key, `/gos unban Name` the old ban by name first, then this realm's, and says so when no ban stood
  there. The /who scanner selects and whispers a connected realm's player by the whole name /who gave
  (`RecruitScanner:Addr`). The group inspector, the rank
  lookup, the roster log and the raid's guild check compare whole keys. Forever and Anniversary keep the name
  alone.
- What is left of attunements and consumables follows their modules, on Forever too, where they were as
  inert (ADR-0014; issue #184): trial progress, export columns, the "no consumables" penalty, readiness.

### Consequences
- (+) One build, one TOC, three clients; Forever and Anniversary behave as before.
- (+) A retail guild sees nothing it cannot use: no loot screens, no site.
- (−) Nothing reads Mythic+, delves or hero talents yet. *(Mythic+ and the delves' vault row since issue #187; see
  below.)*
- (−) A ban added on retail by a client from before issue #184 is filed under the name alone (and holds on
  every realm, as before); one added after it is not seen by an officer still on the older addon, which
  looks the name alone up. Worse, that officer's x on a row named "Bob-Gallywix" lifts `bob`: a ban filed
  under the name alone, if there is one, is lifted for every client, and Bob-Gallywix stays banned. A
  tombstone carries nothing that tells it from a deliberate lift of the old ban, so it is not filtered:
  officers update before lifting retail bans. ChehulNet's v9 must reach the other addons that ship it.
- (−) `MELEE_SPECS` must follow retail when a spec is added (Devourer came with Midnight).
- (−) The profession catalog and Raid Tools' spell ids must follow retail's patches.
- (−) Retail's tiered reagents are not in the catalog, and whether `IsPlayerSpell` answers for retail recipes is read
  in game (`/guildos probe`); the open profession window still fills what it misses.
- (−) Attendance counts an old raid run on Normal, Heroic or Mythic like a current one.
- (−) A retail session relayed by an officer on an addon from before issue #177 carries no difficulty, so it is not
  merged with the same night's session that has one: the raids panel shows that night twice until the officer
  updates and the next sync fills the difficulty in. Attendance is not affected: its lockouts ignore difficulty.
  *(Changed by issue #182: the lockout carries the difficulty, and a night with none does not count; see below.)*

**Amendment (issue #182).** The site leg is on: guildos.me takes retail guilds (guildos-web specs/056, behind its
`RETAIL=1`). CompanionExport and CompanionImport load on retail, and with them the Web tab, `/gos web`, `/gos roster`,
the inbox (roster, calendar, the Discord's cores) and the site link; Look stays absent, since the site draws a retail
character from the Armory. Only the loot verbs remain in `RETAIL_ABSENT`.
- Payload v10, retail's: `game = "RETAIL"`, `region` from `GetCurrentRegion()` (`Compat.Region`: 1 us, 2 kr, 3 eu,
  4 tw), `guildKey` and `realm` from the guild's home realm (`GuildOS:GuildRealm`, the database key's rule), never the
  exporter's, and each session's `difficulty`. Any other region publishes nothing and says why
  (`Companion:Refused`, shown on the Web panel). Forever and Anniversary send v9's bytes under `v = 10`.
- The enchant summary asks `GearAudit:NeedsEnchant`, so the site and the member sheet agree about an off hand.
- `RaidTracker.RAID_KEYS` has Midnight's four raids by map id, under the site's catalogue keys.
- On the way back the key is the name: a GOSROST v3 member is invited and grouped by its `Name-Realm` key, cut to the
  plain name only on this character's realm; who is already in the group is known by name and realm; a name the site
  never confirmed is rescued only when one connected realm has it. `RaidFor` needs the same difficulty when the
  planned raid and the night both have one. A GOSCORE is this guild's by its home realm, normalized. The names kept
  from the site are the `Name-Realm` keys, the same on every officer's client, so the calendar's list of answers
  matches across connected realms; a raid member the client keeps secret is passed over. The JSON decoder moved
  from SoftRes, absent on retail, to Core/Utils.lua.
- Attendance as the site counts it (its `lockoutKey`, `apps/web/test/parity.test.ts`): a lockout is core, instance,
  week and, on retail, difficulty (`RaidTracker:LockoutKey`), so Normal and Heroic in one week are two lockouts, as in
  the game. A retail night counts for progression by its difficulty (`Is25Man(instanceID, size, difficulty)`): one
  with none, relayed by an addon before issue #177, does not, nor is it the same lockout as that night's recording
  with one. TBC and Forever keys are unchanged. `tools/attendance-parity.lua` with `RETAIL` prints the site's retail
  fixture and checks its answers.
- (−) A region the site has no world for (China, a test client) cannot publish. `GetCurrentRegion()`'s answer on the
  maintainer's client is read in game.

**Amendment (issue #183).** Personal loot has a history on retail. Nothing hands loot out there, so LootMaster, Points,
SoftRes and Wishlist stay absent and their verbs keep saying so *(points, the wishlist and a loot council by trade come
back with issue #185, below)*; LootTracker and LootEquity load, and with them the
`lootTracker` background feature, the Loot tab (History and Equity; no Soft Res button, no loot-master line), the
roster's LOOT column, the dashboard's loot card, the digest's loot line, the member sheet's loot section, `/gos equity`,
the `loot` and `equity` exports and the loot list in the companion payload, in today's row format. The Settings loot
category stays out: everything in it hands loot out.
- `LootTracker:OnEncounterLoot` records `ENCOUNTER_LOOT_RECEIVED`, registered on retail only: every guildmate's item,
  not only mine, in the shape an ML award has, plus `itemId` and `encounterID`, and no `fromML`. `player` and
  `playerKey` are both the whole `Name-Realm` by the player's own realm (`GetPlayerKey`): the event names someone on
  this character's realm without one, so a bare name meant another person to an alt on a connected realm, and
  `/gos equity`, which groups by `player`, merged namesakes and split one person. Forever's grouping is untouched.
- Only inside a tracked raid session whose instance and difficulty this client stands in. Raid Finder of the same
  raid queued in the 20 minutes is the same instance id with strangers' items. In that grace, on retail, another
  instance or the session's raid on another difficulty takes no snapshot, opens or closes no boss and records no loot
  for the session (`RaidTracker:ElsewhereInGrace`); back in the session's raid on its difficulty all three count, as
  when the zone change was missed. When the grace runs out, or another raid begins, while the client is elsewhere,
  the session ends with no `session_end` snapshot (`EndSession(away)`, asked before the timer is cleared): the Raid
  Finder or pickup group there would otherwise join the session's players and give every guildmate the late-leave
  penalty. The open world is the run-back and keeps its snapshots, and Forever and Anniversary are as before.
- Guild members only (the coordinator's decision): the player has to be on the guild roster by that key
  (`Compat.FindGuildRosterIndex`, then `KeyOfRosterName`), so a guildmate on a connected realm counts and a namesake
  from another realm does not. On Forever a record needs an award from this guild's officer; on retail any member's
  client would otherwise send a pickup raid's strangers to the guild's loot page, `/gos equity` and the digest.
- A field the client keeps secret skips the whole item; a record without it would be half a record. Under Rare (the
  loot master's default threshold) is not kept; an item not cached yet is read from its link (`|cnIQn:`, the name in
  brackets), else taken as epic, as an ML award is. The same boss, item and player within five minutes is a re-fire,
  checked against the history itself, so it holds across a /reload.
- Forever and Anniversary never register the event, and `OnEncounterLoot` returns at once there; `RecordMLAward` stores
  what it is given exactly as before.
- (−) Each client records what its own client was told. A guildmate who was not in the raid has no history of it, and
  two officers publishing the same night send one row each when their clocks put the drop in different seconds (the
  site keeps one row per player, item and second). An ML award has always behaved the same way.
- (−) Whether Midnight fires `ENCOUNTER_LOOT_RECEIVED` for every player's loot, as the boss banner shows it, and whether
  any of its fields arrive secret, is read in game.
- (−) A guildmate the roster has not loaded yet, or who left the guild before the loot arrived, is not recorded.

**Amendment (issue #187).** Midnight's consumables, Mythic+ and the Great Vault. Decided by the coordinator for the
maintainer ("pode resolver as últimas issues"), in autopilot; the calls below are recorded as made.
- **The consumable check comes to retail.** `ConsumableChecker` loads on Anniversary and retail (absent on Forever):
  flask, food, augment rune and weapon enhancement. The buffs are spell ids from `Data/ConsumablesRetail.lua`, written
  by `tools/consumable_catalog.py` from wago.tools' DB2 for 12.1.5.70448: the current expansion is the highest
  `ExpansionID` a consumable carries (11); a flask is a Flask (class 0, subclass 3) whose on-use spell raises a rating or
  a stat (aura 189 or 29), which leaves out the Haranir profession phials (aura 511) and the PvP flask; the rune is an
  Other consumable (subclass 8) whose spell raises a stat; food is the spells named Well Fed or Hearty Well Fed that
  raise a stat, above the expansion's own Become Well Fed (1219179, the spell its food ticks; the buff that follows is
  the server's and linked to nothing in the data, and The War Within's last Well Fed is 465481). Four flasks, one rune,
  94 food buffs. A weapon oil or stone is a temporary enchant, not an aura: only my own is read
  (`GetWeaponEnchantInfo`); nobody else's reaches the client, so it is never asked for a raider but me.
- **Unknown is never missing.** Auras are read through `Compat.UnitBuffIDs` with `Compat.IsSecret` on the aura and its
  id: nothing in combat, nothing while `C_Secrets.ShouldAurasBeSecret()`, nothing for a unit that shows no buff at all
  (out of range). A list with a secret entry, or with a buff past the fortieth (retail has no 40-buff cap), is partial:
  it can find a buff, never declare one missing. Each raider's
  row lists `unknown` beside `missing`; `/gos cons`, the popup and the readiness column count only `missing`, and say how
  many could not be read. A raider of whom nothing was read has no count, never "all missing". Readiness matches a raider
  by key alone on retail: a namesake on a connected realm is another raider. The announce (`/gos consreport`) names only
  what is missing, and is held back in an encounter's chat lockdown, which would drop it.
- **When it reads.** Out of combat: on READY_CHECK and again on READY_CHECK_FINISHED (retail only) the raid is read
  quietly, so whoever eats or flasks in answer to the check is read with it on; every out-of-combat snapshot reads it
  too. A snapshot in combat (the pull's `encounter_start`) answers with the verdict read out of combat in the last 600
  seconds (`ConsumableChecker:Recent`, session state), else nil; a later reading that could not read never wipes an
  earlier one.
- **The penalty.** A snapshot's `hasConsumes` is true, false, or nil when unread (retail). The score counts a snapshot
  as a hit unless it is known to be without (`~= false`): the player is docked when the snapshots they were known to be
  without are more than half of the ones that saw them. CompanionExport's `chits` counts the same way, so guildos.me's
  rule (`chits / snapshots < 0.5`) gives the same verdict with no new payload field; on Anniversary every value is a
  boolean and nothing changes, and Forever's are all true. The penalty setting, the readiness column, the dashboard
  card, `/gos cons` and the Settings test follow the module onto retail; the readiness tab gains a Check Consumables
  button, since the Raid HUD (the TBC way in) is not there.
- **Mythic+ and the vault (`Modules/MythicPlus.lua`, retail only).** Each member's own client reads its rating
  (`C_ChallengeMode.GetOverallDungeonScore`), its keystone (`C_MythicPlus.GetOwnedKeystone*`) and its vault
  (`C_WeeklyRewards.GetActivities`: the raid, dungeon and world rows; a delve fills the world row and its level is the
  tier) through Compat, never a secret value. The record keeps `mplus = { rating, key = { map, level } }` and
  `vault = { at, raid/dungeon/world = { n, best } }` (slots open and the best level; a raid's best by difficulty rank,
  Raid Finder lowest), sent in the member broadcast: absent from an older addon, never null; what the client cannot
  give yet keeps the old value. The rating is read only after CHALLENGE_MODE_MAPS_UPDATE (asked for at start-up) and
  the vault only after WEEKLY_REWARDS_UPDATE, so a 0 or a vault of empty rows read before the server's data never
  overwrites the real one guildmates hold. A run's end, a vault update or the season's data sends one broadcast two seconds later.
- **Where it shows.** The member sheet: MYTHIC+ (the rating in the game's colour, the keystone named in the reader's
  language) and GREAT VAULT (raid, dungeons and world, x/3 with the best level), the vault only when it was read after
  this week's reset by the reader's clock (`C_DateAndTime.GetWeeklyResetStartTime`). An optional roster column, M+,
  offered on retail alone. Members without the addon: nothing. The companion payload does not carry them.
- **A separate delves tracker is out**, as are hero talents.
- (−) Whether Midnight keeps raid members' auras readable out of combat inside a raid instance is read in game. If
  `ShouldAurasBeSecret` holds there all the time, the check reads nothing in raids and docks nobody.
- (−) Whether WEEKLY_REWARDS_UPDATE fires at login without the vault being opened is read in game; if it does not, my
  vault goes out only once its progress changes or the vault window opens.
- (−) The catalog follows retail's patches: a new flask or food is a new spell id, and the Well Fed rule rests on
  Become Well Fed staying the expansion's anchor.
- (−) The weapon is read for me only; a guildmate's oil is never counted.
- (−) `chits` now means "snapshots not known to be without", where guildos-web's type comment (packages/goscomp) says
  "seen with". The site's arithmetic needs no change; its wording does, on the site's side.
- (−) `GetOverallDungeonScore` and the keystone APIs are trusted to answer for the player after
  CHALLENGE_MODE_MAPS_UPDATE; the vault's enum numbers fall back to 12.1.5's (raid 3, dungeons 1, world 6).

**Amendment (issue #185).** Retail hands loot out again, built on what it has: personal loot that can be traded for a
while to someone who was eligible for it. LootMaster stays absent (no Master Loot), and so does SoftRes: softres.it's own
page says "Soft-reserves for your Classic WoW raids!" and names no retail raid (read 2026-10-22), so nothing could be
verified to import. `RETAIL_ABSENT` keeps `lm`, `lootmaster` and `softres`.
- **Points** load on retail: boss-kill EP, manual awards, decay, standings, their export and the DKP tab, as on Forever.
  An entry is named by the whole key there (`Points:MakeEntry`), as the loot history names a guildmate. An item is
  charged when an award by trade is recorded, never from Master Loot. `Points:OnBossKill` awards nothing while its pool
  is not set up (the module switched off).
- **The guild's loot system** decides who awards an offered item, on every member's client, so on retail an officer's
  choice is published (`guildcfg`/`lootsys`, stamped like the officer threshold, re-sent on the officers' regular sync;
  newest stamp wins). Forever keeps the setting each client's own, as before; a client before #185 reads a `lootsys`
  envelope as a threshold with no `max` and drops it. TMB, Classic only, is not offered on retail; "rolls" is the free
  roll there. The Settings Loot category returns on retail with the loot system and the points; the loot master's and
  the loot distribution's sections are the loot master's and stay out.
- **The wishlist** loads on retail. Its items come from the Encounter Journal at run time for Midnight's raids (journal
  instances 1307, 1314, 1308, 1320; `Compat.JournalLoot`), every class's, never read while the journal is open, its
  filters and instance put back after; read again on `EJ_LOOT_DATA_RECIEVED` until every list is whole. An item not
  cached yet is found and wished for by the journal's name (`Wishlist:ItemFacts`). A list is filed under its sender's
  whole key, never the name it carries, so namesakes on connected realms stay apart and nobody files a list under a
  guildmate's name. Delivered, on retail, is any history row of mine: personal loot or an award by trade.
- **The loot council by trade** (`TradeCouncil`, retail only; `UI/TradeCouncil.lua`). A guildmate offers a tradeable item
  from their bags (`/gos offer [item]`, the council's Offer buttons, the Offer button on their own recent row of the loot
  history; Settings' quick access opens the council for every member). The offer goes to the raid on its own prefix
  (`GuildOSTC`: `O|id|free|secs|drop|link`, `A|id|choice|link`, `W|id|winner`, `X|id`, `D|id|winner|by`); only a
  guildmate's message over RAID is read, and a link only when it is one item link: no control character, a link's own
  colour (`|cffRRGGBB` or retail's `|cnIQn:`), and inside the brackets no `|` but the crafted-quality atlas
  (`|A:Professions-ChatIcon-Quality-...|a`, at a chat icon's size) and no bracket, since a link is printed, put on a tooltip,
  relayed to raid chat and stored (and uploaded) as an uncached item's name. Guildmates answer Need, Greed or Pass with
  the item they wear in that slot (the lower of a pair). The council ranks the answers Need, Greed, Pass, then by the
  guild's system (DKP points, wishlist place), then the server's roll; it shows who wished for the item (by name, with
  the realm when it is not this one: `GuildOS:DisplayKey`), each player's attendance and points.
- **Who awards.** An officer, or the offer's holder when it was made under the free roll: the holder's client says so on
  the offer, and every client believes it only when the guild's loot system it holds is the free roll, so no holder
  makes their own item theirs to award. Only to a guildmate who answered Need or Greed (an `A` this client saw), never
  a Pass. Once an award a client saw names a player, that player's answer stands there: a later change is refused on
  their client (they are told so) and ignored on every other, so the trade's `D` still finds what the award was
  given for. Each awarder's latest award is kept per offer (`awards[by] = winner`); the last one shows. The winner is
  announced in raid chat.
- **The trade.** When the holder trades the item to the winner (`TRADE_SHOW`, `TRADE_PLAYER_ITEM_CHANGED`,
  `TRADE_ACCEPT_UPDATE`, then "Trade complete." in `UI_INFO_MESSAGE` however long the other player took, and the item
  in the window must be the offered one: this link, else the same item id), the award is recorded:
  `LootTracker:RecordTradeAward` turns the holder's row of that drop into the winner's (`awarded`, `from`), or adds one
  on a client that missed the drop, stamped either way with the drop's time the offer carried (`drop`, the holder's own
  history; the offer's time when it has none, and on a receiving client also when the holder's figure falls outside the
  trade window it could have come from, two hours and a minute back to now), so every client writes the same row and the site keeps one. The holder's
  `D` tells every other client the award as the holder saw it, winner and who gave it. **A `D` is believed only for an
  award this client saw given** (a `W` from `by` naming that winner, given for a Need or Greed that then stood; or,
  under a free roll, `by` the holder, to a guildmate who answered Need or Greed), to somebody still in the guild: before this, any raid guildmate could send an offer and
  a `D` naming an officer as the giver and have that officer's client charge a guildmate's DKP and every client write
  them a loot row. Every client then records that one award, whichever it saw last, so two officers awarding at once
  charge once: the officer named in `D`, and only for the award that client gave (`awards[me] == winner`), under DKP
  with a cost per item. An offer this client closed a little early (its trade time is read in whole minutes, so an offer
  runs a minute past it) still records the holder's `D`. A trade of an offered item to anyone else records nothing,
  says so and withdraws the offer.
- **What the client really exposes for trade time** (12.1.5.70529's API documentation, read 2026-10-22): no function
  answers it. `C_Container.GetContainerItemInfo` says `isBound`; the time is only on the tooltip, a line of type
  `Enum.TooltipDataLineType.TradeTimeRemaining` (36) in `C_TooltipInfo.GetBagItem`'s data, whose text is
  `BIND_TRADE_TIME_REMAINING` with a duration. `Compat.TradeTimeLeft` finds the line by its type (any language) and
  `Compat.TradeSeconds` reads the duration with the client's own `INT_SPELL_DURATION_*` / `D_*` strings, every plural
  form. Unreadable, the holder can still offer: the offer runs at most two hours and shows the time as unknown.
- **The roll** is the server's. A player's first Need or Greed on an offer sends the answer, then, once the answer has
  really gone out (`Compat.SendAddonMessageNow`'s `onSent`: not while a lockdown's queue holds it or a throttle retries
  it, or the roll's line would reach the raid first and bind nothing), `/roll 1-100` (`Compat.RandomRoll`); every client binds that player's next 1-100 roll line (`CHAT_MSG_SYSTEM`, read with
  `RANDOM_ROLL_RESULT` by `GuildOS:MatchFormat`, as the loot master reads rolls) seen within 10 seconds after the answer to
  it, the earliest waiting answer first when one player answers several offers. A roll seen before the answer, of
  another range or after the wait is nobody's, and a changed answer keeps its roll, so nobody fishes for a better one;
  an answer whose roll was not seen ranks after those whose roll was. No answer goes in a chat lockdown, where the
  roll's line is secret to everyone: the player is told to answer after the encounter. (A first cut hashed the offer id
  and the player instead; the holder chooses the id, and could try ids until a friend out-rolled the raid.)
- **Midnight:** a secret message, sender, tooltip line or trade partner is never read; addon messages sent during an
  encounter are held by `Compat` until the lockdown lifts (offers happen after the boss), and the award's chat line is
  printed instead of sent in a lockdown (`Compat.SendChatMessage`).
- **Wishlist sync on retail** is taken only from a guildmate over GUILD (`HandleWishlistBroadcast`'s channel); a
  stranger's list was stored under their key and shown as a guildmate's. Forever and Anniversary as before.
- Words: retail's onboarding privacy step and the About text name the wishlist, which is shared once a player keeps
  one; the officer step points at the Loot settings (free roll, Wishlist or DKP).
- Forever and Anniversary: TradeCouncil does not exist (`/gos offer` says "Not available on this client."), the wishlist
  reads no journal and keys lists by name, points and the loot system are as before.
- (−) An offer lives in the session: a holder's /reload loses theirs (offer it again); a client that missed the offer,
  the winner's answer, the award or the holder's `D` records nothing of that award; one that missed a player's roll
  line ranks them last. The DKP charge needs the awarding officer's client to see the
  trade's `D`: one that left the raid before it charges nothing.
- (−) The loot history is append-only on guildos.me: an item published as the holder's before the trade stays the
  holder's row there too, beside the winner's.
- An award by trade is recorded with the Loot Tracker switched off in Settings, as a master-loot award is: the switch
  is for what drops, an award is the guild's decision. The DKP charge rests on the holder's word that the trade went
  through (the winner confirms nothing), as a master-loot award's rests on the loot master's.
- (−) Read in game: whether `C_TooltipInfo.GetBagItem` carries the `TradeTimeRemaining` line and the duration words
  `TradeSeconds` reads; whether "Trade complete." arrives as `UI_INFO_MESSAGE` with `LE_GAME_ERR_TRADE_COMPLETE` or the
  string; whether `GetTradePlayerItemLink` gives the bag's very link; whether the `EJ_*` functions answer with the
  journal never opened, and fill the list after `EJ_LOOT_DATA_RECIEVED`; whether addon messages over RAID reach every
  connected-realm guildmate in the raid; whether a connected-realm player's roll line names them with their realm, and
  arrives within ten seconds of their answer.

---

## ADR-0027 — The lockout week is the region's, from the client's own reset table

### Context
A lockout is core, instance and week (and on retail its difficulty), and the week started on Tuesday 00:00 UTC on
every client: `RaidTracker:GetWeekNum` counted from 3 January 2006, and the raids panel kept its own copy of the
constant. The game resets each region at its own hour. A Monday-night raid in Brasília after 21:00 (Tuesday 00:00
UTC on) landed in the week after its own, which split a guild's one lockout in two or merged two into one, and a
Tuesday-night raid in Europe the same; on all three games (guildos-web#199).

### Decision
- The week is counted from the region's weekly raid reset. The table is the client's own `Cfg_Regions.Raidorigin`,
  rows 1 to 4, the same in retail 12.1.5.70448 and 70529, WoW: Forever 1.60.1.70450 and 70532 and TBC Anniversary
  2.5.6.70006 (wago.tools/db2/Cfg_Regions, read on 22 Oct 2026): `us` 1127228400 (Tuesday 15:00 UTC), `eu`
  1135742400 (Wednesday 04:00 UTC), `kr` and `tw` 1135810800 (Wednesday 23:00 UTC). Every reset since is the
  origin plus whole weeks. A constant (`RaidTracker.RESET_ORIGIN`): an addon cannot read a DB2 table.
- The region is `Compat.Region()` (`GetCurrentRegion()`). Any other answer, or none, counts the Americas' week, as
  the site does.
- One helper: `RaidTracker:GetWeekNum` and `WeekStart`. `LockoutKey` (both lockout counts, the attendance rebuild)
  and the raids panel's week groups and their dates ask it; the panel's own epoch is gone. A week's heading in
  Brasília now reads Tuesday to Monday.
- `C_DateAndTime.GetSecondsUntilWeeklyReset`, where the client has it, is a cross-check in `/gos selftest`
  (`raidtracker.weekly_reset`, through `Compat.SecondsUntilWeeklyReset`), never the source. `/guildos probe` records
  whether it and `GetCurrentRegion` exist.
- The Great Vault's week (ADR-0026's #187 amendment) is not this one: the vault is the game's, so the member sheet
  asks the client when its week began (`Compat.WeekStart`, `C_DateAndTime.GetWeeklyResetStartTime`). Kept apart on
  purpose when the two branches met: the lockout week has to be the site's, the vault's has to be the game's, and on
  retail the self-test says when the two disagree.
- guildos.me counts the same weeks from the same table (its `packages/wow/src/reset.ts`), by the guild's region.
  `tools/attendance-parity.lua` prints the Americas' fixture and, with `REGION="eu"`, Europe's, with nights either
  side of both resets, and the site checks both to the digit (`tools/reset-week.lua` checks the rest).

### Consequences
- (+) A guild raiding Wednesday and Monday nights in Brasília has one lockout a week, as in the game; a European
  guild's Tuesday night is the last of its week.
- (+) Nothing stored changes: attendance is rebuilt from the sessions at every login (`MergeDuplicateSessions`
  rebuilds it), so each client's numbers move at its first login on this version.
- (−) Attendance near the boundary changes for existing guilds, on purpose: lockouts that were split in two become
  one (one chance fewer in the denominator, and the late or left-early penalty for whoever came to only one of the
  nights), and nights merged across the real reset become two.
- (−) Officers on versions either side of this one disagree about those weeks until both update; the site follows
  this version.
- (−) If Blizzard moves a region's reset, the table has to follow; the self-test says when it disagrees.
- (?) Whether `GetCurrentRegion` and `C_DateAndTime.GetSecondsUntilWeeklyReset` exist on WoW: Forever and TBC
  Anniversary, and agree with the table, is read in game (`/guildos probe`, `/gos selftest`).

---

## ADR-0028 — A character's own pack, outside the switch, in the export's one field

### Context
`Companion:IsEnabled()` is off by default because the export carries the whole guild. guildos.me's companion became
an app for any member (the site's specs/070): somebody who installs it and signs in with Discord has no reason to
know about `/gos web on`, and with the switch off the addon wrote nothing for it to send.

### Decision
- With the switch off the logout writer stores a pack: the export's wire format and decoder, `members` with the
  player's one line, `self = true`, and none of what only an officer's upload may say.
- It sits outside the switch on purpose. The switch exists for the guild's data, and this is one line in a file on
  the player's own PC, which only leaves it when somebody is logged into the companion.
- **One `GOSCOMP1:` string per file.** The app lifts the first regex match, so an export and a pack side by side
  could send an officer's upload the pack. Both live in `GuildOSDB.__companion`, so neither the app nor `payloadRe`
  changes. Switch on: the export and no pack, and a failed build removes a leftover pack (`__companionSelf` says what
  the field holds) while it keeps a good export, as it always has. Switch off: the pack and no export.
- `loot` is an empty list, not absent: `packages/goscomp`'s `assertPayload` refuses a payload without one. Every
  other guild field is absent.
- The pack never stamps `__companionAt`: the Web panel's "last written" and Activation's publish step read that as
  the guild publishing.
- It asks `IsOnGuildDB`, not only `GetGuildInfo`. A db that never resolved reads the switch as off whatever the guild
  chose, and a pack there would replace that officer's export.
- The line comes from one `memberLine`, so the two cannot drift, and the guild's rank and the unit APIs feed it: a
  quick relog has no roster loaded. What a roster fills in as a default (a rank nobody gave, an average of 0) is
  absent here: the site writes what it is given.

### Consequences
- (+) A member's own gear reaches the site with no setting, no window and no officer.
- (+) The export is byte for byte what it was: `tools/companion-payload.lua`'s output did not change.
- (−) The string is the account's and the switch is the guild's. An officer who logs out on an alt in another guild
  leaves that alt's pack in the field, and a pending export waits for the next logout on the main. Exports are whole
  snapshots, so that is a delay and nothing is lost.
- (−) A token-holding companion with the switch off now sends the pack to `/api/ingest`, which answers 200 and writes
  nothing (`self: true`, guildos-web#323). The site has to be deployed before this release, or an older `/api/ingest`
  would take a pack for a one-line roster.
- (?) Whether `IsInGuild`, `UnitClass`, `UnitLevel` and the rank from `GetGuildInfo` still answer at PLAYER_LOGOUT on
  WoW: Forever is read in game, from 4 November. If one does not, the pack is not written and the export is untouched.


## ADR-0029 — Recruitment: ads that cross zones by whisper, a request that is asked in the game, and a probe for what only a client proves (guildos.me #071, #245)

### Context
A guild's recruiting ad (`CR2`, then the sealed `CR3`) travelled by GUILD, group and YELL, and YELL stops at the zone
and at the layer. A character with no guild had no way to ask one to take it, and an officer had nowhere to see who
asked. Nothing in the repository proves that an addon whisper to "First Surname" reaches on WoW: Forever, that a
created channel carries an addon message from a timer, or what the game says when an invite goes: no client was
available before 4 November.

### Decision
- `Modules/ChehulGossip.lua` carries what a client holds past the zone: each client keeps a list of who it heard on the
  `ChehulRecruit` prefix and, every `ROUND_SECONDS`, trades a digest (`CRD`) with `ROUND_PEERS` of them. What one lacks
  comes back (`CRG` asks, the ad answers) with a few names (`CRP`). The beacon (`CRB`) is presence plus one ad in turn.
  Everything is bounded: a round's allowance, `REPLY_MAX` per peer, `SENDER_MAX` heard per sender, a list of names read
  only from someone I sent a digest. GuildOS's alone: the mesh library ships identical in the sibling addons and does
  not change.
- It whispers only after it has proved a whisper of its own comes back (`CRW`, to myself, a few seconds after login,
  first with the space the game writes, then the hyphen of the character folders). The spelling that came back is the
  one used; none, and gossip and requests stop whispering and the screen says so (`:CanWhisper()`). The test needs a
  chat filter that hides the "no such player" line of a name tried; without one there is no test.
- `Modules/JoinRequests.lua` is the request: `CRQ` repeated while the player is online, `CRA` the answer (officer and
  member say where it got to, invited and declined end it). The guildless side keeps `GuildOSDB.recruitOutbox`
  (account-wide) and writes the open ones to `recruitOutboxWire` (a `GOSOUTB1`) on logout for the companion. The
  guild's side keeps `db.joinRequests` (fifty at most) and tells the site through the export's optional
  `joinRequests` (v13). Invite is only ever called from a click (`Compat.NeedsClick`) and the row is closed only by the
  game's own `ERR_GUILD_INVITE_S` line, never by the click.
- Two repairs from the last review: a request decided while the person was offline comes back under the game's id and
  finds its row by `gameId` (it used to make a new open row, and the officer got a notice and an Invite button for
  somebody already declined); and the invite's confirmation names the person whole (`sameInvited`: space and hyphen are
  one, no prefix, and on retail the realm is compared when both sides have one). `sameName`'s prefix stays for the CRQ on
  purpose: a person may have asked as "Ana" and be "Ana Lima".
- `/gos probe channel` (button in Audit > Sync) joins a channel of its own, sends from the command and from a timer,
  listens for its own text and leaves, always. The result is `GuildOSDB.probeChannel = { timer, click, timerSkipped,
  clickSkipped, heard = { timer, click }, joined, left, at }`: `timer` and `click` are true (the game took it), false
  (tried, and it did not) or nil (never tried, and `<how>Skipped` says why: the channel had no number yet). A second
  press while it runs retries a skipped click. `GuildOSDB.probeChannelOpen` holds the running channel's name, so one
  that a `/reload` cut short is left: by `Probe:Initialize` a moment after login, or by the next run before it writes
  its own. `Gossip.CHANNEL = false` ships the route off: with it on, the beacon goes through
  `GuildOSNet` and not by YELL. Only a new version turns it on, after the probe has run in a real client.
- The Audit panel (Sync) shows, from `Gossip:Audit()` (a copy is kept in `GuildOSDB.recruitAudit`, nothing goes to
  the site): rounds, ads in and out, known peers, discards, the whisper spelling or that none came back, requests open
  / asked / delivered, invites sent and how many times the game's invite line came back, drops by name and by guild,
  and the channel probe's result. Every source is read in its own `pcall`.
- What the last whole-branch review changed, each of them something the pieces only showed running together:
  - A guild keeps its own ad. `RB:IngestCR3` takes it only over GUILD and from who `Gossip:IsOfficerSender` calls an officer: a
    whisper in that name (the check drops the realm) or a member is refused, and `want` never asks for it, at any
    version. That is how a member holds the ad, says the guild in `CRB`, is found by `:PeerFor` and answers a request as
    `member`. A roster not loaded yet vouches for nobody and the officer's next repeat lands: no mechanism of its own.
    `:Prune3` never cuts that ad, and among ads of one validity cuts the oldest version: an export gives a whole list
    one `x`, and the night with more guilds than seats is when a member most needs its own.
  - The companion's list goes on the gossip (the owner's call in spec 071, "o ChehulNet repassa a quem não tem
    companion"). `digest` and `pull` read `Held`: the cache and the live ads of the list, one per name, the
    newer version and at the same version the list's. The list is copied into nobody's cache, the ceilings and the
    digest's order are the gossip's, the seal still comes from one's own `GOSRECR1` alone, and `x` goes out as it is and
    is cut to 72 hours on the way in.
  - A client offers only what somebody it can reach can use: its own faction and region (`GF:Reaches`), any ruleset,
    because the addon cannot read one. An ad with no faction is a guild with no roster yet, and goes. What it cannot
    judge it does not offer, rather than everything: a client that does not know its faction passes on the faction-less
    alone, one that does not know its region nothing, and an ad with no world is not offered. The filter comes before
    the choice of one ad per name, so a namesake elsewhere hides nobody. `want` reads all the client has and not only
    what it offers: an ad kept and not offered, asked for every round, would be the loop a guild once ran on its own ad.
    The guild's own ad in the cache always goes: it needs no judging, and without it the beacon says no guild. A list
    entry is only spelled like this guild and goes through `Reaches` like any other, or a member would serve another
    guild of that name and claim it. On retail `Reaches` also asks for a realm that can invite this character. A namesake
    of the same faction and region on another ruleset still passes: it comes from `ad.key` being the name alone, which
    stays, and the addon cannot read a ruleset anyway.
  - Who is an officer, for what only an officer may say over GUILD, is `Gossip:IsOfficerSender`, the one door of both
    the guild's ad and a decision. `IsOfficerByName` compares the part before the hyphen, so a roster with `Bruno Reis`
    and a sender spelled `Bruno-Reis` would refuse the officer: no member holds the ad, no decision crosses the guild,
    on launch night with nothing to see. It stays as it is, because other modules rely on it. On WoW: Forever the door
    reads the roster itself, both sides lower case with hyphens as spaces, the whole name against the whole name, never
    by prefix and never `IsOfficerByName`, whose first question gave the false positives: with hyphens on the roster or an
    officer with no surname it took `Bruno-Melo` for Bruno. Only this client's own realm comes off the end, by
    `Import.PlainName`, so a roster with a realm keeps working.
    Elsewhere a hyphen means a realm, and `IsOfficerByName` is right. `officerRefused` in `Gossip:Stats()`, on
    the Audit panel, is the senders refused right now: one vouched for later leaves it, so a roster that came late is
    no noise on every login, and what stays is the failure this exists to show.
  - A number off the network goes through `GuildOS.Finite`, and every check on one says what must hold, never what
    refuses. NaN answers false to every comparison, so a whisper `CR3|Ordem|...|nan|nan` once replaced a held ad, `want`
    then refused the real newer version, and a second client held the forgery within half an hour; inf passes any
    `> 0`; and `tonumber` takes both as text. A NaN or inf reaches no saved table: a NaN in SavedVariables is an unknown
    risk to the whole `GuildOSDB` file. That covers CR3, CR2 (where it would also have deleted), the beacon, the digest,
    a request's level and the `at` of `GOSRECR1` and `GOSGILD1`, which `SiteJoinRequests` wrote onto a saved row; a date
    that is no number is too old to believe, never good for ever. `RB:Prune` drops what a save already holds wrong.
  - `probeChannelOpen` is cleared only once the channel is seen gone. A leave from a timer may be dropped with no
    error, so `Probe:LeaveStaleChannel` looks again `STALE_AGAIN` seconds later and leaves at most `STALE_TRIES` times, and
    what is still there keeps its name for the next login or key press. `FinishChannel`'s leave is one of those tries.
  - The whisper test goes over the spellings `TEST_PASSES` times, `TEST_AGAIN` seconds apart, and its token lives the
    session: an echo that comes after the last try still counts. With one pass, a lagged opening night left a client
    with no gossip and no requests until a `/reload`.
  - An officer's `Broadcast` pauses where the gossip does (`Gossip:Quiet()`), and on Anniversary, where the gossip does
    not run, it goes on as it always did.
  - A request from the site is told once the rank is known: the row is born `unheard`, `:Refresh` runs from
    `OFFICER_START` as well, and the first reading where `IsOfficer()` holds tells it, once. A block's request keeps its
    `source`, so one made in the game can be invited only when its person is heard.
  - Deciding is an officer's and inviting is the game's. Who can invite below `officerMaxRank` sees no Decline, the row
    stays open after their invite, and `:Decide` prints why it refused. A card with no slug promises no companion:
    `WriteWire` passes over it, because the site could not tell whose guild it is.
  - Left as it is, on purpose: `ad.key` is the name alone, so two guilds of one name in two worlds share a slot (changing
    it changes the contract).

### Consequences
- (+) A new ad crosses zones in rounds, not in the time one yell takes to reach the next client.
- (+) A request that nobody sees is still kept and goes to the site through the companion.
- (+) The opening night leaves in `GuildOSDB` what happened in a real client, with no `/dump`.
- (−) Everything that uses a whisper depends on a test that waits ten seconds after login and on a filter, and a client
  whose echoes come very late stays off the gossip until one does.
- (−) With a list longer than the cache, a client at the cap keeps asking for older ads it cannot keep: the traffic sits
  at the ceiling, and never over it.
- (−) A member with nothing saved who logs in with no officer online has no ad until one comes: a guildmate's whisper of
  it is refused, and costs that guildmate one answer of its round.
- (?) Only a real client proves: whether the space or the hyphen is the spelling a whisper arrives with on Forever (and
  whether either is); whether `JoinChannelByName` gives a channel a number in the same frame or a moment later (the
  command's message is not tried when it does not: `click` stays nil, `clickSkipped` says why and a second press
  retries it); whether a timer's message into a channel
  is dropped on Forever as a timer's GUILD line is; whether the channel's join and leave lines are hidden by
  `CHAT_MSG_CHANNEL_NOTICE`'s filter (the probe's are; the live route's are not, and it ships off); and whether
  `ERR_GUILD_INVITE_S` is the line a Forever invite prints, which `confirmed` in the Audit counts. If it never comes
  back, an invite never closes its row by itself and the site's roster ingest does.
- (?) And, from the last review, what no harness can reach:
  - **The first three reads on 4 November**, before anything else: `/dump GetGuildRosterInfo(1)` on Forever, which says
    the roster's format and which the officer check, the invite and the keys all rest on; the Audit panel's
    `officerRefused` at 0 with an officer online, which says the guild's ad and decisions are crossing GUILD; and which
    whisper spelling came back, in the same panel.
  - Whether a sender's name reads as the roster's. `Gossip:IsOfficerSender` covers a space or a hyphen on either side and
    this client's own realm on the end. A sender that carries any other realm is refused: the whole name is what is
    compared, and a Forever client's realm string is not known to be the same for two people. `officerRefused` shows it.
    `sameName` has the same exposure: a sender spelled differently drops a real `CRQ`, silently.
  - Whether the text of the "no such player" line is `ERR_CHAT_PLAYER_NOT_FOUND_S`, and whether AceComm echoes a whisper
    to oneself on a client where it splits a message.
  - Whether a `CR3` of a real list, by whisper and by GUILD, stays under the chat limit on an opening night: the ceilings
    are counted in messages, and nothing here measures what the game calls too much.
  - Whether `/w Chehul-Costa` opens the right whisper, and `GuildInvite("Chehul Costa")`, with the space the game gave,
    reaches who was meant. It is the Alt-click's pattern, and that one is proven only for a name off a whisper.
  - Whether `GetRealmName()` says the ruleset on Forever: until then the World filter offers the ones in the list.
  - Whether `STALE_WAIT` is long enough for the game to have joined a character's channels, on a login and on a `/reload`.
  - Whether the game drops `LeaveChannelByName` from a timer at all, and how long a leave takes to show in `GetChannelName`.
  - Whether `tonumber("nan")` reads as NaN on the client as it does in LuaJIT, and what writing one to SavedVariables does.
  - Everything on a screen. The finder, the form, the notice and the list were only ever drawn on fake widgets: the
    drop-down menus and their arrow and check, layout, line wrap at 700x480, `SetEnabled` on Invite.


## ADR-0030 — The guild's trial: a length worked out on every read, and new members by the roster seen (#249)

### Context
A trial lasted 30 days, hard-coded, each trial stored its own `endDate`, and the first client to notice the end stamped
it `"expired"`. Trials travel between officers as the whole table (`TR`), the latest activity winning, so a length
written into each record would be undone by any officer still on the old version, whose copies carry the old end.

### Decision
- The length is the guild's: `settings.trialDays` (1 to 90 whole days, nil = 30), `settings.trialAuto` (the switch for
  new members, off by default), each stamped and sent on `guildcfg` like the officer threshold (`trialdays`, `trialauto`;
  newest wins, a tie keeps the shorter length and the switch off). Neither payload has `max`, which a client before
  this reads as the threshold.
- **A trial's end is never read from the record.** It is `startDate` + the guild's length, in `EndOf`, every time. A
  change moves every running trial both ways, and nothing an old client sends can move it back. `endDate` is still
  written on a new trial, for the old clients that read it. A stored `"expired"` is a trial nobody decided, like
  `"trial"`: lengthened, it is running again. Only approved and denied are decisions. Nothing writes a status at login.
- New members come from the roster alone: an officer's client keeps the roster it has seen (`db.trialBaseline`, keys
  only), and `ScanRoster` is the only path that starts an automatic trial, for a join a moment ago and for one while
  no officer's addon watched alike. The join line (RosterLog) only asks the game for a fresh roster: its name is never
  made into a key, because on WoW: Forever it need not be the roster's spelling ("Chehul-Costa" against "Chehul
  Costa", a first name alone from `UnitName`), and two strings for one person would be an orphan trial beside the
  real one.
- **The baseline is the officer's, and only grows.** `GuildOSDB` is the account's, one table per guild, so a
  non-officer alt that kept it would take the officer's newcomers in unseen: a non-officer client neither reads nor
  writes it, and a newly promoted officer with none only records at the first look. Each character's last look is
  remembered by its own key (`db.trialScannedAsOfficer`): a look made while it was no officer (demoted, or outside a
  narrowed threshold) forgets it, and the first look as an officer again only records, like a fresh install, so a
  re-promoted officer never reads a month of members as new. A scan only adds keys; a key
  leaves only on a leave or kick line (`OnLeave`), so a roster that comes short never reads the rest of the guild as
  new. Turning the switch on (here or heard, on an officer's client) drops the baseline so the next roster is only
  taken; heard on a client that may not touch it (an alt of the account), it leaves `db.trialBaselinePending`, and the
  next officer's look honours it as a look that only records, then clears it. Nothing moves while the roster is not whole or the rank is unknown, and a roster that shares nobody with the
  one seen is taken, not read as newcomers (the keys changed under it).
- **A login waits.** `Arm` (MODULE_START, every login and /reload) keeps ScanRoster from comparing or touching the
  baseline for `SETTLE_SECONDS` (60), the time for the guild's settings and the other officers' trials to arrive,
  then runs it once by itself, roster event or not.
- **Two undecided copies of one trial keep the earlier start**, both copies' notes and the longer snapshots: an
  officer whose catch-up started the same person later (the first officer offline, or its `TR` not yet arrived) neither
  restarts the trial nor drops what was written. **An automatic trial never reopens a decision:** nobody with a trial
  record in any state (undecided, approved, denied, left) is auto-trialed, and in `Merge` an automatic copy (sponsor
  "Guild OS") gives way to an approved or denied one whatever their dates, with both copies' notes; an officer who never
  saw the approval cannot put that member on trial again. Otherwise, with a decided copy involved, the latest activity
  still wins, so an officer's own new trial after a decision carries; it keeps the decided one's notes.
- A whole roster read by an officer marks an undecided trial whose member is missing (`leftAt`, a field, not a status,
  so old clients carry it), and clears it when they are back. Such a trial is counted nowhere (login line, digest,
  Agora, suggestions, presets) and the panel lists it with the decided, "left the guild"; it still syncs.
- A trial started this way is sponsored by "Guild OS", the same on every client, so two officers' copies of one join
  meet as one trial in `Merge`; nobody on an officer rank and nobody already unresolved is started.

### Consequences
- (+) The officers choose the length once, and every officer's list agrees, old versions included.
- (+) A guild that turns the switch on gets every newcomer as a trial without a click, caught up at the next login.
- (−) An officer on an old version still flips trials to `"expired"` by their own stored end and shows them so; the
  new version reads that as undecided and works it out again, but the old client's screen is its own.
- (−) The catch-up starts the trial at the officer's login, not at the join: there is no join date to read.
- (−) A whole-roster pass on every GUILD_ROSTER_UPDATE, as DropDeparted already does.
- (−) A trial starts when the roster next answers, not at the join line itself: the request is the game's to throttle.
- (−) Somebody who left while no officer's addon read the line, and comes back, is still in the baseline: not
  auto-trialed. Accepted, against a short roster ever putting many members on trial. The same when a leave line spells
  the name otherwise than the roster (Forever).
- (−) Restarting an undecided trial by hand does not travel: the other officers keep the earlier start.
- (−) Somebody who comes back after an approval or a denial is not auto-trialed: an officer puts them on trial again
  by hand (Mark as Trial), which keeps the old notes.
- (−) Known limit: a roster that comes short with every row answering reads as whole, so it marks `leftAt` on the
  undecided trials of everybody it leaves out, and they drop out of every count until the next whole roster clears it.
- (−) Known limit, erring the safe way: on an account's shared database, an officer character's first look after this
  update, or after a re-promotion, only records the roster, so newcomers the main officer had not seen yet (one who
  joined with only a non-officer alt online, or with everyone offline) are not auto-trialed.
- (−) A login's newcomers wait a minute; with no officer online to answer, the catch-up uses the settings this client
  had.

## ADR-0031 — One answer a window, one roster pass a window, and a meter that stays (#324)

### Context
An officer of a 700-member guild on WoW: Forever reported high CPU one morning, with no logs. Every REQUEST from any
guildmate made every online client answer on GUILD at once: a member with its own data and three small messages, an
officer with ~36 (25 roster-log events, alt links, eight guild settings, its own data: 41 chunks, 5.8 KB, ~6 ms of
compression in LuaJIT without the JIT). A login sends three requests and every client one every ten minutes; the
whole guild decodes every answer, and ChatThrottleLib's 800 B/s, shared by every addon of the client, takes ~7 s to
send one officer answer, so a login wave kept the queue from ever draining. Every GUILD_ROSTER_UPDATE ran four
passes over the whole roster and redrew the open window. Nothing kept how often either arrived.

### Decision
- `CommSystem:HandleRequest` answers at most once per `ANSWER_GAP` (120 s). A request inside the window is held, and
  the window's end answers once for all of them: nothing asked goes unanswered, it waits two minutes at most. A
  `/gos sync` asks with `NOW`, answered within `NOW_GAP` (15 s), so its 20-second report still counts who answered;
  a NOW inside an ALL's window brings the held answer forward. A client before #324 reads NOW as ALL.
- `GuildOS:Coalesce(name, gap, fn)` runs a call at once, holds what comes inside `gap`, and runs the last one at the
  window's end. The roster passes, the chat class cache, the window title and the Now tab go through it with
  `ROSTER_GAP` (5 s).
- `GuildOS.Perf` counts and times, per label, the guild sync in and out by type and SyncService domain, the requests
  answered and held, the roster events and passes and the window's redraws, and `/gos perf` (Audit > Sync) shows them
  with the game's own addon meter when the client has one. It ships on, since a report of high CPU never comes with
  a profile.

### Consequences
- (+) An officer answers once every two minutes whatever the guild's size, and the guild decodes one answer per
  client per window instead of one per request.
- (+) A burst of roster events costs two passes.
- (+) The next report comes with numbers: `/gos perf` names where the time went.
- (−) A guildmate who logs in right after somebody else's request waits up to two minutes for the data of those who
  just answered; their own data still goes out every five minutes.
- (−) Every officer still answers the same window; one answering for all would need them to agree, left out.
- (−) A roster change shows on the open window up to five seconds late in a burst.
- (−) Two clock reads per timed call, always on.

## ADR-0032 — A journal entry is said again while its author is online, ahead of member data (#327)

### Context
Each client writes down its own clears and milestones and tells the guild once (`add`), then once more at its next
login (`snap`, its last week). Member data is pushed every 5 minutes and pulled every 10, so a lost broadcast heals;
nothing healed a journal entry. Filhos da Horda's officer file (2026-11-12) shows the cost: Chuleta Maximus's clear of
Excavation Site was written by his client at 01:57 UTC, and the officer was online then (its own roster stamps at 01:51
and 01:59) and stored his member data at 02:51 and again at 15:05 in a later session, without the clear; it arrived
only after 16:57, fifteen hours and three of his sessions later. A groupmate's clear took a later session too. The same
file shows why it could be lost while both were online: those clients' member data arrived 5 to 49 minutes after it
was collected, where nearly the whole guild's arrives inside 5 seconds. GuildOS sends everything through one BULK pipe
in ChatThrottleLib, first in, first out; an entry written at the end of a run waited behind that queue, and what is
queued at a logout or a `/reload` never goes.

### Decision
- `journal` messages go at ChatThrottleLib's NORMAL priority. ChatThrottleLib shares its bandwidth between the
  priorities that have something queued, so an entry (one or two messages, a few a day) leaves within a second however
  deep the BULK pipe is.
- `Journal:Snap()` runs every 10 minutes while online, as well as 30 seconds after login: an entry that went to nobody
  who uploads, or was lost on the way, reaches every client that is online with its author for 10 minutes in that week.
  Receivers already keep an entry once, by its id.
- Still only from its subject: nobody relays another member's entries, so an officer who never shares 10 online minutes
  with somebody in a week still misses that person's week.

### Consequences
- (+) A clear reaches the officers online with its author within 10 minutes, and the companion's upload with them.
- (+) A priority and a ticker; no new message, and an old client reads the snapshots as it always did.
- (−) Every member with an entry in the last week sends one small snapshot every 10 minutes (27 members had one in
  Filhos da Horda's file; one to three messages each), next to member broadcasts of about ten messages every 5 minutes.
- (−) The BULK backlog itself is not addressed: member data from those clients still arrives minutes late.

---

## ADR-0033 — Weekdays and months come from the translations, and a date's layout is translatable (#307)

### Context
The game's `date()` writes `%a %A %b %B` in English on every client: a frFR calendar said "Monday, 09 Nov 2026"
under a grid whose weekdays were French (`L["Mon"]`). Twelve calls did it, in the calendar, the Dashboard, Now, the
alliance screens, the guild chat and the Web panel.

### Decision
- `GuildOS:LocalDate(fmt, timestamp)` takes `date()`'s own format and fills those four conversions from `L` before
  `date()` sees it. It lives in Core/Core.lua, so every harness that draws a date already has it.
- A whole date's layout is an L key holding a `date()` format (`L["%A, %d %b %Y"]`): a language reorders it, puts the
  year first (koKR, zhCN, zhTW) or names the month in full (`%B`, the month headers). Only `%a %A %b %B %d %H %M %Y
  %m %y %%` are allowed in a translation, since an unknown conversion can raise inside `date()`.
- `"May"` is one key, the short and the full month alike, so every language gives the full name, short enough for both.
- `tools/date-names.lua` scans every file the TOC loads for a `date(` call whose string literals (an L key included)
  name a day or a month, and fails naming the file and line.

### Consequences
- (+) English is exactly what `date()` wrote; every other language reads its own names and order.
- (+) A new raw `date("%a")` fails in CI, not in a support channel.
- (−) The scan follows literals inside the call only: a format kept in a variable first is not seen.
- (−) Names are nominative: a language that declines a month after a day (ruRU) uses the short form, which does not.

---

## ADR-0034 — The kinds of event below the officers: the guild's, a separate guildcfg action, held both ways (#308)

### Context
Since #283 the guild chooses which ranks create calendar events, but not which kinds: whoever could set up a dungeon
run could set up a raid.

### Decision
- `settings.eventKinds` (a list of `Calendar.KINDS`; nil = every kind, as before) and `settings.eventKindsAt`, an
  officer's choice published on `guildcfg` as its own action, `eventkinds`, with `{ kinds }` and no `max`: a client
  before this reads an unknown guildcfg action as the officer threshold, and one without `max` it ignores. Not folded
  into `events`' payload, whose `max` every #283 client already reads, so neither setting can undo the other.
- Newest stamp wins; two in one second settle on the fewer kinds, then on the list that, written in `KINDS` order and
  joined by commas, sorts first as text (`DUNGEON` before `RAID`), so every client agrees whatever the order. Re-sent
  with the ranks on the officers' sync and request answer.
- An officer creates every kind. A kind is held only when an event is created or its kind changes: `Create` and
  `CreateSeries` refuse a closed kind, `Update` refuses a switch to one. An event a member already made stays theirs
  whatever the officers close later: edited, rescheduled, its series changed or ended, cancelled, deleted. On receipt
  `OnSync` drops a non-officer's `create`/`update` of a closed kind unless this client already holds that event with
  the same kind.
- A Dungeon event offers the game's dungeons (`Calendar:DungeonChoices`: WoW: Forever's own with a boss, then the classic
  ones guildos.me books, `ForeverDungeons.classic`) beside the title; the pick is the title, so nothing new travels.

### Consequences
- (+) An old client is unchanged: it never hears the choice and takes every kind, and an old officer never resets it.
- (−) A member on an old client can still send a closed kind; clients on this version drop it, old ones keep it.
- (−) A list names the kinds of its day: a kind added later is closed to members until an officer ticks it.
- (−) An officer on a client before this tops up a member's series that this version dropped: its new dates come from
  an officer, so they are taken.
- (−) A kind this version does not know (one a later version adds) is read as RAID on receipt (`normalizeKind`), so a
  member's event of it stands or falls with raids being open.

## ADR-0035 — Groups: a listing is the leader's on the guild channel, a request is a whisper, and looking stays `LG` (#341)

### Context
Members asked for a group finder inside the guild. The addon had the availability board (#243): a role, a note and a
duration on `LG`, drawn by a popup. It could not name an activity, and there was no group with open spots to ask into.

### Decision
- **Looking stays `LG`**, with two fields an older client never reads: `roles` (a subset of `THD`) and `acts` (up to six
  activity ids). `role` still goes out, the single role or `ANY`, so a client before this shows the listing as it did.
- **A group is a new message, `GF`**, on GUILD only, keyed by the sender, one a leader: `{ act, note, need, n, max, ttl,
  age }` or `{ clear }`. Not folded into `LG`: an older client would list a group as one more player available. Not
  `LP` either: that is the wishlist's loot prio, matched by its literal in `OnMessageReceived` (`tools/groups.lua`
  holds that no code is used twice).
- **A request for a spot is a whisper, `GJ`**, and is accepted only from somebody on the guild roster by their whole
  name (a namesake on another realm is nobody, as #78), only by somebody leading a group, only for a role with a spot
  open. `LG` is likewise heard on GUILD alone now. Its answer (`decline`, with `closed` when the group came down) is
  a whisper back. Requests live for the session (`GuildOS.State.groups`), listings are saved.
- **The spot closes by the party, not by a click**: when a queued player is in the leader's group their role's spot
  closes; no spot left, or a full group, takes the listing down. The game's roles are not read: Classic has none.
- **Activities are ids from a per-client catalogue** (`Data/GroupActivities.lua`). An id this client does not know is
  kept and shown as "another activity". Names are the client's own by map id where it knows the instance.
- **The game's art is drawn only when the client says it has the file** (`Compat.TextureExists`): the paths are the
  LFG frame's backgrounds as Classic names them, unverified on WoW: Forever, and a missing path draws a green square.
- The leader publishes at most once every 6 s and receivers take one listing a sender every 5 s; an asker sends one
  request a leader every 3 s against the leader's 2 s. What only removes a matching entry (a `clear`, a `cancel`, a
  `decline`) is never held to a cooldown: it happens once an entry, and the one dropped would leave a row that is no
  longer true.
- A request belongs to the listing it was made for: another activity or an expiry empties the leader's queue and the
  asker's memory of it. Only whoever can invite (alone, leader, raid assistant) lists a group.
- The window's tab label padding went from 20 to 18 px: with the Groups tab an officer's sixteen tabs no longer fit
  the rule at 1000 px, which `tools/window-shell.lua` holds.

### Consequences
- (+) An older client is unchanged: it keeps the board it had and drops `GF` and `GJ` as unknown types.
- (+) Nobody publishes, changes or takes down somebody else's listing, and nothing off the wire reaches a row unsanitised.
- (−) A request needs the leader online, which a listing already does (a leader who logged off is not listed).
- (−) A member invited by hand closes no role's spot: the open spots are only capped at the seats left, cut from the
  last role back, until the leader says which.
- (−) On WoW: Forever a queued player is matched by first name when the unit's name carries no surname (#48): a
  guildmate who shares it would close the spot early.
- (−) Groups do not cross to allied guilds; the alliance keeps seeing who is looking, without the activities.

## ADR-0036 — The core's owner: the site in a linked guild, the game otherwise (guildos-web specs/085; #347, #339, #340)

### Context
A core lived in two places and was born in two: on Discord (`/core criar`) and in an officer's client. The site's
decision (specs/085) is that in a guild linked to the site the site's database owns a core's existence, its people and
its configuration, and the game owns only what happened in the raids; in a guild without the site the game owns
everything. Until now cores reached the game only through the companion's `Inbox.lua`, and nothing went back.

### Decision — a second way in, and a receipt out (#347)
- **A pasted GOSCORE1 is the inbox's package.** The roster box (`ShowImportPopup`) takes a `GOSCORE1:` code too;
  `CompanionImport:Load` sends it to `CoreManager:ImportPasted`, which checks the officer and hands it to
  `ImportPackage`, the one path the inbox also takes: the same guild and realm check (`notOurs`, which now says which),
  the same site clock (`db.discordAt`, newest `at` wins, an undated package is older than a dated one), the same
  `ImportFromSite`, the same chat line. `CompanionImport.ReadCores` reads both strings: the companion's alphabet, a body
  under 256 KB, the `fmt` and a `cores` list. The officer who pasted sends the lists at once (`SendDiscordChanges`):
  the rank is known, unlike at login.
- **`coreReceipt` in the upload**, within v16 as `why` was: one more absent field, behind the Raids module and its
  own `optional()`. `linkedAt` is `db.coreLink.importedAt` (the last own import, inbox or pasted, that was not older);
  each Discord core's `importedAt` is when this client last applied a Discord list to it (an import or another
  officer's list). Figures are clamped integers, so the hand-written encoder never writes an exponent.

### Decision — a linked guild creates no core in game (#339)
- **Linked** is stored: `db.coreLink.since`, set by an own import with cores or a heard `discordList`, cleared by an
  own empty package, by the last release heard (no core holds a tag) or by an officer's "create in game again". A
  guild from before (a core holding a tag, no record) is linked at `Initialize`.
- **Creating** goes through `Create`, which a linked guild refuses with where to create; the import and the
  `discord`/`discordList` actions use the local `newCore`. `GetCore` no longer makes a core for an unknown name in a
  linked guild: the raid's free tag, a sign-up and another officer's `update` roster make none (their points fall to
  the guild's pool, as a raid outside a core). The panel's input becomes a sentence.
- **The Discord's rename** follows on the next import, by `moveCore` (the body of `Rename`): the core is the tag's, and
  its name follows only when it carried the Discord's previous name (`core.discordName`), so a core named by its tag or
  linked by hand keeps its own; never onto a name another core has. `discordList` carries `discordName`, so an officer
  without the companion renames too.
- **The loot rule** of a Discord core is the site's while the roster in hand carries one (`LootRuleFromSite`): the
  GOSROST1 names no core, so the rule the site sends counts for every Discord core of the guild.
- **30 days quiet** (`seenAt`, the freshest package: the inbox's ack, a paste, another officer's `seenAt` on its
  list): the officer hears it once and the panel offers "create cores in game again" (`CreateInGameAgain`). That
  choice marks `releasedAt`, which makes every package up to it older (the same inbox at every login links nothing),
  and goes to the officers online as releases with `off = true`.

### Decision — a pug is a guest of the night (#340)
- **`core.guests`**, apart from `core.members`: `GetComposition` and `OpenSlots` read the members alone; the night's raid
  (`RaidRoster`, `CoreForGroup`) reads both. Attendance and loot candidates come from who is in the raid group, so a
  guest in it counts there already.
- **Who becomes one**: in a linked guild an officer's "add" on a Discord core (`AddToRoster`, the picker and a name
  field for a pug outside the guild) and a sign-up accepted there; anywhere else "add" is a member, as always.
  Migration: whoever is on a Discord core without `src = "discord"` becomes a guest marked to stay, so nobody
  disappears; it runs at login, after an own import and after a heard list, which keeps a Discord core's members all
  the Discord's.
- **The night ends** with the raid session (`RaidTracker:EndSession`, a kept session only): its guests leave, but those
  marked to stay.
- **Sync** is a change, `core.roster`/`guests` `{ put, gone }`, never the whole list: an officer's guests are never taken
  off by another's message. A client from before ignores it (no `members`).

### Consequences
- (+) A guild where no officer runs the companion can still receive its cores.
- (+) An older site ignores the receipt; an older addon never had the paste.
- (−) A Forever package pasted into an Anniversary client of a guild with the same name is not told apart: the GOSCORE1
  carries no game, and the realm check is the inbox's (a Forever package has no realm).
- (−) The decompressed size of a pasted code is not bounded by LibDeflate; the 256 KB on the encoded body bounds it to
  what deflate can expand that to.
- (+) A guild that never imported a GOSCORE1 sees no change.
- (−) A client before this version in a linked guild still creates cores and sends their rosters; clients on this
  version ignore a roster for a core they lack.
- (−) A core renamed in game to the Discord's new name no longer reduces to its tag: the site counts its nights by the
  core's name (`coreTags`), but anything on the site matching only by `slugOf(groupTag)` (the idle check) does not.
- (−) The site's rule locks every Discord core's rule while the roster in hand carries one, not only the raid's core.
- (−) Guests are heard only by the officers online when they change: an officer who was away keeps the guests they
  had until the next change, as the Discord's lists before #138.
- (−) The night ends on each officer's client with its own raid session: an officer who was not in the raid keeps the
  night's guests until the officer who was sends who left.

---

## ADR-0037 — One dropdown, and one Loot window for the rule, the accounts, the lists and the history (#346)

### Context
- No control picked one of several values: the screens used a button that turned to the next value on each click (the
  loot method, the threshold, the raid size, the role, the account shown, what an answer asks for, an exception's kind).
  A player could not see the choices, nor land on one without passing the others.
- Each loot setting was edited in two or three places: Settings > Loot (the active core's, or the guild's), the core's
  Config tab (that core's), the rule's own window, the points window, the DKP tab and the Master Loot window
  (`wishlistOnlyMode` in three). Each wrote the same keys by its own path, with its own checks.
- The Loot tab was officer-only, so the Dashboard's "your loot" sent members to a tab they could not open.

### Decision
- **`UI:CreateDropdown`** in UI/Helpers.lua, the one factory: a `CreateButton` that shows the value, and one list the
  addon shares, built on first use, anchored under the button that opened it, closed by a click outside it (a
  transparent sheet under the list), by Escape (UISpecialFrames, as every popup of the addon) and by a choice; ten rows
  then a scroll. Painted by `StylePopup` and `CreateButton`, so both interface styles draw it. Every control that
  picks among more than two values on the loot and core screens is one; two values stay a pair of buttons.
- **The Loot window** is one tab (`loot`, every member's) with sub-tabs Rule · Accounts · Lists · History. An officer
  edits, a member reads. The Rule tab has a selector (the guild or a core) and is the only place the loot system,
  the loot master's settings, the answers' editor (`BuildLootRuleEditor`, moved, not copied), the council and the
  exceptions are edited; under them, "how players will read it" (`LootRule:Describe`). The Accounts tab is the points
  window of before on the core picked (`Points:InCore`), with the award row and the points' own settings. Lists holds
  the wishlists and the soft reserves; History the history and the equity.
- **The old places point here**: Settings > Loot and the core's Config tab keep one line, "Loot: <rule> — Open
  Loot" (`GuildOS:DrawLootPointer`). `/gos points`, `/gos dkp` and `ShowPointsFrame` open Accounts; `dkp` and
  `wishlist` stay features (their Settings switches) without a tab of their own (`opens = { tab, sub }`).
- **Writes go through the modules**: `LootMaster:SetLootSetting(key, value, scope)` (the same keys, checked as the
  screens checked them, written where `CoreManager:SetLootConfigKey` writes) and `Points:SetConfigKey(key, value, core)`;
  the award row is `Points:AwardRow`.

### Consequences
- (+) Each setting has one place, and one check; a guild that changes nothing keeps every stored key and behaviour.
- (+) A raider reads the rule their raid plays and their own balance.
- (−) The loot master's settings in Settings followed the raid's active core; the Rule tab opens on that core too,
  but an officer now sees which one is being changed and may pick another.
- (−) `wishlistOnlyMode` unchecked on a core is now stored `false` (it was `nil`, which fell back to the guild's).
- (−) Escape closes an open list and, like every popup of the addon, the windows behind it.

---

## ADR-0038 — Bulk rank changes and removals: one member per click, through a secure button (#420)

### Context
- Officers asked to promote, demote or remove many members by rules (offline for days, rank, level, raid
  attendance, without GuildOS), as other addons do from a button or a macro.
- `GuildPromote`, `GuildDemote` and `GuildUninvite` are protected: an addon's call is `ADDON_ACTION_FORBIDDEN`,
  from a click too (ADR-0010). The addon had no secure frame until now.
- On WoW: Forever an addon-written `/ginvite` on a secure button was `MACRO_ACTION_BLOCKED` (#256).

### Decision
- **`Modules/BulkActions.lua`** picks the members (pure `Rules` / `Eligible` / `Meets` / `Match`) and keeps the
  queue in `GuildOS.State.bulk` (session only). It never calls a protected function, never loops over the
  queue and never acts from a timer or an event.
- **The Next button** (`UI/BulkPanel.lua`) is a `SecureActionButtonTemplate` named `GuildOSBulkNext`, created at
  the first moment out of combat after load (never in combat: its size and backdrop would be refused), so a
  `/click GuildOSBulkNext` macro works before the tab is opened. Its PreClick asks `BulkActions:Arm`
  for the line of this click only (the game's own `/gpromote`, `/gdemote` or `/gremove` for one member, written
  by `Compat.GuildRankCommand`) and sets it with `Compat.SetSecureMacro`; the game runs it; PostClick marks the
  member sent and clears the line. Before each click the member is read again from the roster, by the whole
  name it gave (never a short-name match): who left, whose rank moved or who no longer meets the rules is
  skipped. The removal's confirmation queues exactly the list it showed.
- **Combat.** Attributes are set out of combat only. The button leaves the window on `PLAYER_REGEN_DISABLED`
  (a window holding a protected frame cannot be hidden in combat) and comes back on `PLAYER_REGEN_ENABLED`.
- **The key-down option.** Where `ActionButtonUseKeyDown` exists (retail, newer Classic templates) the template may
  act on the press or the release by it: `Compat.SecureClicks` registers both, `Compat.SecureClickActs(down)` lets
  exactly one arm the line, and `Compat.ClickMacro` gives the macro `/click GuildOSBulkNext LeftButton 1` while
  the option is on (a bare /click arrives as a release).
- **Typed fallback.** On WoW: Forever (`Compat.SecureGuildMacro` false), or after a blocked-action event for a
  rank function of GuildOS raised while a click runs its line (between PreClick and PostClick), the click prints
  the line for the officer to type and goes on. The blocked click's member is never marked sent; a member
  already sent is never put back. A surname's space goes as a hyphen, as `/w` takes it (`WhisperTarget`). `/gos bulk next` is addon
  code, so it never runs the line: it says who is next, or prints the line where it is typed anyway.
- **Permission** is the game's `Can*` (now `Compat.CanGuildPromote/Demote/Remove`, guarded by compat-guard), and
  `Eligible` leaves out oneself, ranks at or above one's own, promotions to one's own rank and demotions below
  the last. A removal starts only after a confirmation listing who.
- **Sent, then done or not confirmed.** A sent member is done only when the roster shows the change; with no
  change 15 s after the click it reads "not confirmed, check it" and is never sent again.
- **The Roster Log** gets a change when the roster shows it (`GUILD_ROSTER_UPDATE`), unless the game's own guild
  message already logged it; `RosterLog:_Insert` also folds the same officer change (action, member, author,
  rank) seen twice within 30 s.

### Consequences
- (+) Bulk changes with one click (or one macro press) per member, inside what the game allows.
- (+) The first secure frame of the addon is in one place, with the combat rules in Compat and the panel.
- (−) Not verified in game yet on any client: the secure macro path is the one other addons use on the Classic
  clients; retail's press/release handling and WoW: Forever's typed fallback follow what #256 measured.
- (−) A rank changed by the click but not yet seen by the roster stays "sent" until the next roster update.

## ADR-0039 — The member history: passages and ranks kept past the log, from merges that never double (#425)

### Context
- Officers asked to see "was a member from X to Y, N days" when they re-invite somebody (Discord; epic #423,
  group C). The Roster Log forgets after 90 days / 1000 events, `firstSeen` is dropped when a member leaves
  (DropDeparted) and no client has a guild join date.
- What happened while the officer was offline reached the log only if another officer's client saw it.

### Decision
- **`Modules/MemberHistory.lua`** keeps `db.memberHistory[key] = { stints, ranks }`, apart from the log and its
  pruning, on officers' clients only, with a ceiling (10 passages and 15 rank changes a member, 4000 keys, the
  former members who left longest ago dropped first; bound ~7.6 MB, a 1000-member guild over three years ~1 MB).
- **Sources:** every event the Roster Log takes (its line or an officer's, `RosterLog:_ToHistory`); a diff of the
  whole roster against `db.memberHistoryBase` (`Scan`, from Core's roster pass through `Coalesce`, at most once a
  minute, 45 s after login so the officers' audit backfill arrives first); the other officers' records.
  A one-time migration takes the Roster Log's events, then an open passage for each present member from the
  earlier of `firstSeen` and `foundingJoins` (marked as only "seen by GuildOS").
- **Merges, not ids, make it converge:** an exact time beats a seen one (`joinEst` / `leftEst`), a kick (with its
  officer) beats a leave beats "gone", two exact records of one change within 5 minutes are one. Applying a
  record twice, or two officers' records of the same change, changes nothing.
- **Sync:** append-only records with an id over the existing `audit` domain, act `hist` (older clients read only
  `add`); receivers apply on an officer's client only. The last 25 records this client sent go again with the
  Roster Log's login backfill. No full-history sync.
- **The diff's own log lines** (level ups by milestone/all/off, public and officer note changes, back from
  30+ days offline, "gone", a join seen at login) are local (`loc`): never published nor backfilled, since every
  officer's client sees the same change and an officer note is not for the guild channel.
- **A rejoin** stays a `join` event with `rejoin = true`: the event id, the near-dup fold and every older client
  stay as they were.
- The TrialTracker's baseline is not shared: it only grows and is about newcomers; this one mirrors the roster.

### Consequences
- (+) Invite, join and whisper tell the officer the past; the log exports; other features read
  `MemberHistory:Stints/JoinedAt/TenureDays/Ranks/LastLeft/Describe`.
- (−) Before the install, or while no officer's client saw the roster, dates are "seen by GuildOS" or unknown.
- (−) A rename is a departure and a join (no GUID tracking yet); an officer who installs late gets only the
  records others still send (the last 25 each) and the log's 90 days.


## ADR-0040 — Alt links: one synced entry per alt, with tombstones; "AL" only merges (#424)

### Context
- Linked alts "kept getting unlinked automatically". The "AL" message carried the whole `altLinks` table and
  the receiver replaced its own with it: no time, no merge, no tombstone. Every officer sent it on every sync
  request and on `/gos sync`, so an officer with an old or empty table (a new install, one offline when another
  linked, a database the game recreated) wiped everybody's links, other officers' included, and an unlink came
  back when an old table was sent again. A member's claim (#353) was dropped when an old list lacked it.

### Decision
- **`Modules/AltSync.lua`**, officer domain `alt` on the SyncService, as the ban list: one entry per alt
  `{ main, author, ts }` or `{ removed = true, author, ts }`, its revision in `db.altSync.rev`. A write takes
  revision max(server time, last + 1), so the newer edit wins across officers and two officers linking different
  alts at once both stand. A tie settles the same way everywhere (`Wins`). A tombstone is pruned after 30 days;
  its revision is kept for good, so an older link for that alt is still refused.
- **Backfill:** officers re-send every entry at its stored revision on a sync request and `/gos sync`, 40 per
  envelope, 2 s apart, one backfill at a time (#324).
- **The view:** `db.altLinks` stays what every reader reads; `AltSync:Rebuild` derives it, flat (no alt of an
  alt; a loop settles on its lowest key), plus a member's own waiting claims (`AltAutoDetect:Overlay`).
  Officer edits (`LinkAlt`, `UnlinkAlt`, `SetMain`, a member's claim applied) plan the new view and
  `AltSync:Commit` writes every alt whose entry differs.
- **Migration:** the old table becomes entries at revision 1 with no author, so any officer's entry replaces them.
- **Old clients:** "AL" is still sent (the whole view, never an empty one) for clients before #424, which keep
  replacing their table with it. Received, it is only a merge: an alt never heard of at all is added at
  revision 1; nothing is removed or changed; an empty table is nothing.
- **A member's claim** goes only when the officers' links carry it, or when an officer's entry newer than the
  claim unlinks one of its characters or links it elsewhere. Missing from a list is no answer.
- **Forever keys:** every key off the network and in the store goes through `LocalMemberKey`.

### Consequences
- (+) No officer's old or empty data can remove a link; an unlink stays unlinked.
- (−) While officers on old clients remain, they still replace their own tables, and an unlink made on an old
  client is not heard by new ones (the merge never removes). The full gain comes when every officer updates.
- (−) Each officer's backfill sends every alt entry (a few hundred in a big guild) once per answered request.

## ADR-0041 — A member with alts removed or gone: the addon only asks, and its answers go through what exists (#426)

### Context
- Officers asked (as in GRM) to be asked about the alts when they remove somebody, to ban the whole group with a term
  and a note, and to hear when a main leaves while alts stay. GRM removes and promotes on its own; the request was to
  ask. `GuildUninvite` is protected (ADR-0010, ADR-0038), and several officers online all see the same guild line.

### Decision
- **`Modules/AltDeparture.lua`**, fed only by RosterLog's detection (nothing while the login settles, `_ready`, nor
  for a line in chat lockdown, `Compat.IsSecret`) and by a Bulk actions removal the roster confirmed. Session state.
- **Removed:** asked only on the client whose character removed them (the line's author is this character), 2 s
  after, or once a removal queue of Bulk actions is through (`BulkActions:Refresh` flushes). Each group once a
  session. The answers: a removal queue (`BulkActions:StartList`, one per click of the secure button, never
  replacing a running queue), or `BanList:AddGroup` (one ban per character, one term, one note, the mark
  "(group of X)"), or nothing.
- **Gone:** a main leaving with alts still in the guild asks each officer online once (by event id and by main).
  "Set A as main" is `SetMain` (synced by AltSync, ADR-0040), "Unlink" `GuildOS:UnlinkGroup`, "Keep" nothing. An
  answer checks the links first: when another officer already answered, it changes nothing ("settled").
- **The ban's `note`** is a field of the entry beside `reason`, cleaned like the alliance's note, and it never
  leaves the client of the officer who wrote it (`BanList.OnTheWire` strips it from every publish and backfill;
  `_ApplyRemote` drops any that comes in and keeps the writer's own on a ban another officer edits). The ban domain
  goes over GUILD, which reaches every member's client, and the addon has no channel only officers read (OfficerNotes
  also goes over GUILD); so, as a warning's chat line (specs/116), it stays local. `group` travels; a client before
  #426 keeps it unread.
- **The dialogs** are GuildOS's own frames (`UI/AltDepartureDialog.lua`), never a StaticPopup (#315).

### Consequences
- (+) Nothing is removed, banned or relinked without the officer's click; no main is promoted on its own; nobody is
  whispered.
- (−) A removal the client never reads (a secret line on retail in an instance, the remover offline) is not asked
  about; MemberHistory's roster diff does not ask.
- (+) No member's client ever holds an officer's note about somebody.
- (−) The note is only on its writer's client: other officers see the ban, the term and the group, not the note.

## ADR-0043 — Birthdays: a member-owned entry per character, and the calendar's dates drawn, never stored (#428)

### Context
- Officers asked for members' birthdays and join anniversaries on the calendar and said on the day (epic #423,
  group E). The calendar's yearly repeat (#358) makes real events, one per date: one series per member would
  fill `db.events` and its sync with hundreds of entries nobody created.

### Decision
- **`Modules/Birthdays.lua`**, member domain `birthday` (GUILD only), modelled on `foundingSelf`: one entry per
  character `{ d, m, at, by }` or a tombstone `{ off = true, at, by }`, newest server time wins, a tie to the
  tombstone. A member writes for their own characters (their key or alt group), an officer for anybody. One
  birthday per person is a READ rule: the newest entry of the alt group. Members re-send their own at login,
  officers backfill all and answer an older entry once a session.
- **Virtual dates**: the calendar asks `Birthdays:VirtualEvents(from, to)` while it draws and buckets them with the
  day's events; `_Occurrences` "yearly" gives the dates (29/02 on the 28th). Nothing is stored or synced as an
  event.
- **Join anniversary**: the current passage's start (MemberHistory), else `firstSeen`; a date from the first look
  at the guild is none.
- **/g line**: an officer's own setting, off; claim, wait 5–8 s, lower name wins, `said` remembered by everyone.
- **Privacy**: day and month only, no year; tombstone on removal; dropped when the member leaves.

### Consequences
- (+) No event sync grows with the guild; the filters cost nothing.
- (+) The birthday follows the alt group as links change, with no rewrite.
- (−) A late officer can still repeat a line when nobody online heard it said that day.
- (−) Join anniversaries differ between officers (history) and members (`firstSeen`).

## ADR-0042 — The member's officer sheet: one long text per member, synced per member, newest wins (#427)

### Context
- Officers wanted a long note per member kept in the addon (GRM's custom note), and the dated notes are
  a list of short entries. The game's officer note is 31 letters and every officer's to overwrite.
- 1000 letters per member through the existing "OA" (the whole notes table in one message) would make
  that one message huge in a big guild, and it has no revision: the last one to arrive would win.

### Decision
- **`db.officerNotes[key].sheet = { text, author, ts, rev }`**, next to `notes` and `tags`, so the
  Forever key migration (`MergeSheet`, #97) carries it (the higher revision stays).
- **The OFFICER addon channel only** (`SyncService.OFFICER_CHANNEL_DOMAINS`, `CommSystem:SendToOfficers`,
  `Compat.OfficerAddonChannel`): over GUILD a member's client gets the bytes even when it drops them, and any
  addon or log there could read them. Published there, accepted only from there. Retail and TBC Anniversary;
  off on WoW: Forever until checked in game (a sheet stays on its client there).
- **Sync:** officer domain `osheet` on the SyncService, as the alt links (ADR-0040): a write takes revision
  max(server time, last + 1), the higher revision wins, a tie settles by text then author on every client;
  an emptied sheet is an empty text, so an older one never comes back. A member's client drops it.
- **Backfill:** every sheet at its stored revision on the answer to a sync request, at most once per 10
  minutes per officer, and on `/gos sync`; 2 per envelope, 3 s apart, one backfill at a time (#324).
- **"OA" sends notes and tags only**, and takes nothing else in; "ON" is unchanged.
- **The hover card** reads an index the roster builds once per refresh (`RosterCard.NewIndex/IndexRow`:
  alt links both ways, each roster line's name, class and online), never the roster itself.

### Consequences
- (+) A clean text of 1000 letters reaches every officer whole; the newest edit wins; old clients keep
  reading the notes as before.
- (−) The game delivers OFFICER by the rank's officer-chat permission, not by Guild OS's officer threshold: an
  officer whose rank cannot hear officer chat gets no sheet. On WoW: Forever, no sync until checked.
- (−) One text per member, no history of edits; two officers editing at once: one edit is lost (the older).
- (−) Every officer backfills every sheet: in a guild with hundreds of sheets, a few minutes of BULK traffic
  per officer at most once per 10 minutes.


## ADR-0044 — Officers' tools on the notes: dates written and read, the safe list, nicknames (#429)

### Context
- Epic #423 group F (what GRM does and GuildOS did not): write the join date (#425's history) into a public or
  officer note, read dates already written there back, never put some members in a bulk removal (#420), tell the
  officers who comes back after a long time offline, and a nickname per member.
- Only TBC Anniversary lets an addon write a note (`Compat.CanEditPublicNote`, #5/#162); WoW: Forever and retail
  forbid `C_GuildInfo.SetNote` to addons. Many writes in a row can draw `ERR_GENERIC_THROTTLE` (#392/#393).

### Decision
- **`Modules/NoteDates.lua`.** A note never loses text silently: an empty note gets the date, one with room gets it
  after a space, one that says it is left alone; another date or no room only from a confirmation showing the old
  and the new note, and a note that changed since the question is asked again. Nothing over 31 bytes is sent.
  Officer note by default (only officers read it); dates GuildOS only saw are off by default (on a guild GuildOS met
  today they are all today).
- **How it writes:** `Compat.CanWriteNote` (Anniversary) → a run writes one note every 2 s, doubled on the throttle
  (the last write re-read, so none goes twice), halved back after 5 calm writes. `ADDON_ACTION_BLOCKED` on a note
  write → one per click of Next (a hardware event); `ADDON_ACTION_FORBIDDEN`, or a client where `CanWriteNote` is
  false but the rank may edit the note (`Compat.RankEditsNote`) → "copy the text": each click shows the whole new
  note selected in a box to paste into the game's roster.
- **The import** reads the first date of the public note, else the officer note; a review lists every one (new,
  earlier than GuildOS saw, same day, later: not taken, history has the exact day: kept); only new and earlier are
  ticked and the officer unticks any. A day taken is kept as "seen" (`joinEst`, `joinSrc = "note"`) at its last
  minute, so the game's own line from any officer still replaces it. This client's history only: the records sync
  sends are diffs and audit lines.
- **`Modules/MemberMarks.lua`**, officer domain `marks`: per member and kind (`safe`, `nick`) one entry
  `{ v, at, by }`, the later `at` winning (ties settle the same everywhere), a cleared one a tombstone for 90 days.
  Sent on a change and, at login and `/gos sync`, every entry in batches of 40, 2 s apart. Applied on officers'
  clients only.
- **The safe list in `BulkActions`:** `memberAt` reads both notes and sets `m.safe`; `Eligible` refuses a removal or
  demotion for it. Preview and `Current` (each click) both go through `Eligible`, so a member tagged after the
  preview is skipped at their click. A promotion still may.
- **Back after N days offline:** the history's roster diff (#425) already logged it; its look now also prints one
  line to the officer with every member back in it. The snapshot then holds them online, so a return is told once.
  The threshold (`backAfterDays`, 30 by default, 0 = no line) also sets the log's "Back".
- **Chat Tweaks** shows the nickname in the prefix, and, when asked, the prefix on guild members' whispers, party
  and raid lines (always hooked, checked per line).

### Consequences
- (+) Nothing an officer wrote in a note is lost without them seeing the old and new text.
- (+) On Forever and retail the same tool works as copy and paste, one member a click.
- (−) The marks' payload reaches every guild client over GUILD (as every officer domain's); only officers keep it.
- (−) An imported day stays on the client that imported it; another officer imports it on their own.
