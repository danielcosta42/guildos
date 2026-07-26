# Tier 4 design (curated set)

Branch `feat/tier4`, cut from `main` (0.34.0). Goal unchanged: be the most complete guild addon and
close the last gaps vs the competitor sweep. Four items, each shipped via the SDD loop (plan +
implementer/reviewer subagents, luacheck 0/0). Standing rule: a design round (ASCII mockup + user
sign-off) before ANY new on-screen UI, even in autopilot; chat/sync-only work skips it.

## 1. Live guild map (biggest visible gap, vs GuildMap)
Show online guildmates on the world map + minimap. Foundation already exists: `Modules/ChehulNet.lua`
broadcasts presence with `mapID:zoneUID` (so ZONE-level placement is free today), the Chehul mesh
(`_G.ChehulMesh`) and `CommSystem` are available, and there is minimap-button infra
(`BRutus:CreateMinimapButton` / `ToggleMinimapButton`). `C_Map` is available (BCC).
- **Granularity / privacy is the key decision** (see the design round): zone-level (reuse existing
  presence, low exposure) vs exact live x/y (flashy, privacy-sensitive). Leaning: zone-level for
  everyone by default, exact live position as an explicit OPT-IN.
- Guild-scoped position over `CommSystem` (guild channel), not the realm-wide presence, so live
  location stays inside the guild. New UI -> design round first.

## 2. "Do I know this pug?" (high value, low effort, reuses existing data)
When you are in a party/raid with non-guild players, instantly tag each member: guildmate / alt of X /
banned / has an officer note / ex-member. Reuses the ban list, `db.altLinks`, notes, and roster. Surface
TBD in the design round (a compact panel keyed off `GROUP_ROSTER_UPDATE`, or party-frame tags, or an
on-demand `/gos pug`). New UI -> design round first.

## 3. Bulk moderation presets (officer quality-of-life)
Saved rulesets in the Leadership panel (e.g. "kick > 30d inactive under rank X", "promote > 90%
attendance") the officer can review then apply in one place. Builds on `GuildManager` +
`GetInactiveMembers` + the existing management sub-tabs. Rank changes stay Blizzard-protected (open the
native panel to confirm, per ADR-0010). New UI -> design round first.

## 4. F1 cold-sync backfill (deferred debt, NO UI)
Ban / audit (RosterLog) / bulletin domains only converge on the next mutation, so an officer offline at
the event never gets the change. Add a pull-path answer in `CommSystem:HandleRequest` (the same login +
periodic REQUEST path the recruitment config and LFG board already ride) so these domains backfill on
login. Sender/officer-trust bound to the envelope, same rules as the recruitment hardening. No UI ->
build directly, no design round.

## Order
F1 can start immediately (no sign-off needed). The three UI features each get their own mockup +
sign-off, starting with the map. Each feature: its own plan under `docs/superpowers/plans/2026-07-25-t4-*`.
