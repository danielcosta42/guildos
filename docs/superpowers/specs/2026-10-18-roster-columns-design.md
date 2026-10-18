# Roster columns each reader turns on, off and reorders

Issue: danielcosta42/guildos#178 · Type: feature

Condensed spec + plan + tasks. Approved in chat with the maintainer on 2026-10-18.

## 1. Problem

A German guild keeps each player's real name in the guild's public note and wants it on the member list, not
behind a hover. More broadly: turn columns on and off and change their order. Today the list draws eight fixed
columns (`COLUMNS` in `UI/RosterFrame.lua`) and drops them right to left as the window narrows.

## 2. Behaviour

- **Default unchanged.** Somebody who never touches it sees Member, Level, Class, iLvl, Race, Last seen,
  Professions and Zone, in that order. Member is always there and always first: it holds the name, the class
  icon and the online dot, and it is what a click opens.
- **Columns** button in the list's toolbar (beside the online filter) and a right click on the header row
  open one panel: a box per column, ▲▼ to move a shown column, **Restore defaults**.
- **Saved per account**: `GuildOSDB.rosterColumns`, at the root like `style` and `font`, so it follows the
  account across characters and guilds. Nil is the default; Restore defaults writes nil.
- **Every column sorts** on a header click, an empty cell last either way (a member without the addon has no
  item level, race or last seen). Professions and Zone did not sort; they now sort as text.
- **Narrow window**: the rightmost shown column goes first. Priority follows the reader's order; only Member is
  required. (Level and Class were required before; at the default order they are still the last to go.)
- **A column the reader cannot use is not offered**, and a stored one that is not offered is skipped, not
  forgotten: an officer who loses the rank and gets it back finds the layout they had. What is offered is
  read again on every refresh, so the table follows a change of loot system, feature or rank while open.

## 3. The columns

| key | Header | Source | Offered when |
|---|---|---|---|
| note | NOTE | public note, `GetGuildRosterInfo` 7 | always |
| officerNote | OFFICER NOTE | `GetGuildRosterInfo` 8 | `Compat.CanViewOfficerNote()` |
| rank | RANK | rank name; sorts by rank index | always |
| offline | OFFLINE | `GuildManager:GetDaysOffline(index)` (the game's, works without the addon) | `GuildManager` |
| spec | SPEC | the synced spec's tree, then its points ("Frost 0/0/51"); sorts by tree | `SpecChecker` |
| roles | ROLES | `RaiderRoster:EffectiveRoles(key)`, letters T/H/D in role colours (plain when offline) | `RaiderRoster` |
| main | MAIN | alt → its main's name; a main with alts → "Main" | `AltRoster` |
| version | VERSION | live mesh version, else stored; red when older than ours | always |
| enchants | ENCHANTS | `GearAudit:MissingEnchants(gear)` count | `GearAudit` |
| attendance | ATT. | `RaidTracker:GetAttendance25ManPercent`, totals memoised per refresh | `raidTracker` enabled |
| core | CORE | names of the cores holding the key | `CoreManager` |
| dkp | DKP | `Points:Get(key)` | `LootSystemShowsDKP()` |
| loot | LOOT | loot history count, one pass per refresh | `LootTracker` and `lootTracker` enabled |
| trial | TRIAL | `TrialTracker:GetDaysRemaining(key)` | officer, `TrialTracker` and `trialTracker` enabled |
| gosNote | GOS NOTE | newest Guild OS officer note | officer, `OfficerNotes` and `officerNotes` enabled |

Modules absent on a client (retail: Points, LootTracker) leave their global nil, so "offered" reads the global.
Left out on purpose: achievements, resistances, attunements, stats, wishlist, soft-res, AFK/DND.

## 4. Design

- `Modules/RosterColumns.lua` owns the preference (Rule 3: UI never writes the db). Pure, no WoW API:
  `Visible(offered)`, `SetShown(key, on)`, `Move(key, delta, offered)`, `Reset()`.
  It stores the shown keys in order, not Member. A stored value that is not a list of strings reads as the
  default. Turning a column on appends it at the end.
- `UI/RosterFrame.lua`: `COLUMNS` becomes the catalogue, keyed. The eight existing columns keep their renderer;
  the new ones are generic: `value(data, ctx)` (the sort value, filled into the member row in
  `BuildMemberList` only for a column whose cell draws it or that is sorted by) and `text(v, data)` (string
  and colour). Sort keys are made once per refresh: lower-cased, and all text when synced data mixed in
  numbers. `RefreshRoster` lays the table out again when the columns it would choose changed.
  `prepare(ctx)` builds a per-refresh index where a per-row read would scan (loot counts, cores, alt mains,
  attendance totals). Rows own one font string per catalogue column; the layout shows the ones in the spec.
- `UI:Relayout(container)` in `UI/Layout.lua`: re-runs a responsive container's layout now if it is visible,
  else on its next show. The panel calls it for every roster instance after a change.
- `Compat.CanViewOfficerNote()`: `C_GuildInfo.CanViewOfficerNote` or the old global.
- `GearAudit:MissingEnchants(gear)`: the rule `GetGuildEnchantAudit` already applied, now shared.
- `RaidTracker:GetAttendance25ManPercent(key, groupTag, totals)`: optional memo of totals per core.

## 5. Tests

`tools/roster-columns.lua` (luajit, no client): default order; on appends, off removes; Member cannot be turned
off or moved; Move swaps with the next offered neighbour and stops at the ends; a not-offered stored key is kept
but skipped; garbage storage reads as default; Reset. `tools/roster-table.lua` builds the real roster panel
under a stub client: the default header, the panel's offer per reader, on/off/move, every new column's value,
sorting with empty cells last and mixed types, a refresh dropping and restoring a column no longer offered, the
narrow window and Restore defaults. Plus luacheck, compat-guard, locales and every harness.

## 6. Tasks

1. RosterColumns module + harness (TDD).
2. Compat, GearAudit, RaidTracker, Layout helpers.
3. Catalogue, rows, header, sort and data in RosterFrame.
4. Columns panel, toolbar button, header right click.
5. Strings in the eight locale files; TOC; functions catalogue.
6. Install in the beta folder for an in-game test.
