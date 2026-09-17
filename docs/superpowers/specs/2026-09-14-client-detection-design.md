# Client detection: know which client runs, and keep TBC-only content on TBC

Issue: danielcosta42/guildos#7 · Epic: #4 · Depends on #6 (start list)

Condensed spec + plan + tasks.

## 1. Problem

Nothing in GuildOS asks which client it runs on: no `GetBuildInfo`, no `WOW_PROJECT_ID`, no capability
check; the only environment probe is `GetLocale`. WoW: Forever (internal build line 1.60.x) is in the
Classic family but carries none of the TBC content, and `WOW_PROJECT_ID` has no Forever value yet, so a
project-ID switch would be a guess.

## 2. Design

### 2.1 `BRutus.Client` (Core/Compat.lua — Rule 4)
Computed once when `Compat.lua` loads, before any module file:
- `version`, `build`, `date`, `interface` from `GetBuildInfo()`.
- `projectId` = `WOW_PROJECT_ID` (diagnostics only).
- `isAnniversary`: `WOW_PROJECT_ID` equals `WOW_PROJECT_BURNING_CRUSADE_CLASSIC` (when that constant exists)
  **and** `20500 <= interface < 30000`. Both signals, so a client that reuses project id 5 is not mistaken
  for it. Anything else, including an unknown client, is "not Anniversary". Nothing infers "retail".
  The project-id half is how the addons already installed on this Anniversary client recognise it
  (Questie, ElvUI, DBM-Core, TradeSkillMaster, the Zygor TBC Anniversary guide).
- `has`: `secrets` (`issecretvalue`), `chatLockdown` (`C_ChatInfo.InChatMessagingLockdown`), `tradeSkillUI`
  (`C_TradeSkillUI`), `tooltipData` (`TooltipDataProcessor`), `guildSetNote` (`C_GuildInfo.SetNote`).

### 2.2 What is TBC content — confirmed against the code

| Content | Where | Outside Anniversary |
|---|---|---|
| Attunements | `Modules/AttunementTracker.lua` | the module does not exist; audit `attune` sub-tab and the member detail attunement section hidden; `/gos attune` and `/gos attune debug` say it is not on this client and are left out of `/gos help` |
| Consumables | `Modules/ConsumableChecker.lua` (TBC flask/elixir buff ids) | the module does not exist; Settings toggle and Settings test button hidden; `/gos cons` and `/gos consreport` say it is not on this client, and `/gos cons` is left out of `/gos help`; RaidTracker's no-consumables penalty is skipped (it already is when the module is absent) |
| Raid cooldown HUD | `UI/RaidHUD.lua` | never created, combat log never registered; Settings toggle hidden |
| TBC-only raid cooldowns | Bloodlust/Heroism and Misdirection in `RaidTools.COOLDOWNS` | left out of Raids > Raid Tools > Cooldowns |
| Wishlist raid catalogue | `RAID_CATALOG` in `Modules/WishlistSystem.lua` (Karazhan → Tempest Keep item ids) | not seeded into item search |
| Resistances | audit `resist` sub-tab (targets are Shahraz, Hydross, Leotheras, Solarian) | sub-tab hidden |

Kept as they are — generic, not TBC content:
- **Wishlist itself.** Per-character wishlists, sync and LootMaster's interest lookup work on any client.
- **LootMaster.** Master loot already runs only when `GiveMasterLoot` and `GetMasterLootCandidate` exist
  (LootMaster.lua:1159) and falls back to trade otherwise.
- **RaidTracker, GearAudit, Readiness.** Instance ids are data; Readiness already reads the absent modules as empty.
- **Companion export shape.** guildos-web's `GoscompMember` requires `attunements` and `att25`
  (`packages/goscomp/src/types.ts:76-78`). Outside Anniversary they are `[]` and `0`, which is what the
  export already sends when the tracker is absent — no contract change.
- **`/gos attune dumpquests`.** A quest-id dump for debugging; it now reads quest completion through
  `BRutus.Compat.IsQuestComplete` instead of the tracker, so it works on any client. `IsQuestComplete`
  gained the tracker's fallback to the global `IsQuestFlaggedCompleted` for that.

### 2.3 Mechanism
- **Module files:** `AttunementTracker.lua` and `ConsumableChecker.lua` return before defining their global
  outside Anniversary. Every reader already treats a missing module as absent; the two that did not
  (RosterFrame's member tooltip, `/gos attune dumpquests`) no longer read the tracker unguarded.
  `StartModule` already skips a missing module without recording a failure, so no login line.
- **Feature registry:** a feature with `tbc = true` is dropped by `UI:AllFeatures` and refused by
  `UI:IsFeatureAllowed` outside Anniversary, read at call time. Set on `consumableChecker` and `raidHUD`.
  The user's toggles in `settings.modules` are never read or written for this.
- **Audit sub-tabs:** `tbc = true` on `attune` and `resist`; `CreateAuditPanel` builds only the allowed ones.
- **RaidHUD:** outside Anniversary the HUD frame is never created and the combat log is never registered;
  `UpdateRaidHUDVisibility` also requires `isAnniversary`.
- **Raid Tools:** `ResolveCoverage` skips definitions with `tbc = true` outside Anniversary.
- **Member detail, help, Settings test:** the attunement section checks `isAnniversary`; the `/gos help`
  lines and the consumable test button check that their module exists.
- **Commands:** one new locale key, "Not available on this client.", in the five locales.

## 3. Tests
`tools/client-detection.lua` (luajit), real `Core/Core.lua`, `Core/Compat.lua`, `UI/FeatureRegistry.lua`,
`UI/Features.lua` and four module files (the attunement and consumable modules, and the wishlist and Raid
Tools, whose TBC content is gated), under stubbed clients: Anniversary (2.5.6, 20506, project 5),
Forever (1.60.0, 16000, project 2), a client reusing project 5 with interface 16001, and an unknown client
(no `WOW_PROJECT_*` constants). It checks:
- the `BRutus.Client` fields, the interface range edges, an Anniversary interface on another project id,
  a client that reports no interface, and each capability flag present and absent;
- quest completion through `Compat.IsQuestComplete`: `C_QuestLog` first, the global fallback, neither;
- the attunement and consumable modules exist only on Anniversary, and starting them elsewhere records no failure;
- `UI:AllFeatures` and `UI:IsFeatureAllowed` drop the `tbc` features only outside Anniversary, and the saved toggles are untouched;
- the wishlist catalogue is seeded only on Anniversary, and the wishlist itself works everywhere;
- Raid Tools lists Bloodlust/Heroism and Misdirection only on Anniversary, and the generic cooldowns everywhere.

Mutation check: 34 hand-written mutants of the detection (each signal, the edges, a missing interface),
the capability flags, the quest completion fallback, the two module guards, the catalogue gate, the
registry filter and the Raid Tools filter; the harness kills all 34.

The audit sub-tab filter, the HUD gates, the member detail section, the `/gos help` lines, the Settings
test button and the command messages are one condition each and are checked in the game. The existing harnesses still pass, and `luacheck` is clean. Manual check on
Anniversary: everything as today.

## 4. Tasks
- [x] `BRutus.Client` in Compat.lua; luacheck read_globals
- [x] Module files return outside Anniversary; RosterFrame tooltip and `/gos attune dumpquests` no longer read the tracker unguarded
- [x] Registry `tbc` field in `AllFeatures` and `IsFeatureAllowed`; `consumableChecker`, `raidHUD`
- [x] Audit sub-tab filter; RaidHUD visibility gate; wishlist catalogue gate
- [x] `/gos attune`, `/gos attune debug`, `/gos cons`, `/gos consreport` messages (five locales)
- [x] `tools/client-detection.lua`
- [x] Help lines, Settings test button, member detail section, Raid Tools cooldowns, HUD creation and combat log
- [x] Docs: ADR-0014, functions catalog
- [ ] Manual check on Anniversary
