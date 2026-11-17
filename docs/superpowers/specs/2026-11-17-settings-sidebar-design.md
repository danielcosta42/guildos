# Settings in a grouped sidebar

Issue: danielcosta42/guildos#365. Asked by the maintainer on 2026-11-17 ("care about usability:
group the settings areas so the addon is more organized"); mockup approved the same day.

## 1. Problem

The panel had five buttons across the top. General held six sections (profile, modules, quick
access, general options, chat, mentions), About mixed backup, diagnostics and erasing the guild's
data, and "Reload UI" sat in About, far from the module switches whose hint asks for it.

## 2. The sidebar

```
Settings
+------------------+-----------------------------------------------+
| YOU              | PROFILE                                       |
| |Profile         |  Roles I play   [Tank] [Healer] [Melee] [Rng] |
|  Chat & alerts   |  UI scale       [ 1.00 ]                      |
|                  |-----------------------------------------------|
| GUILD OS         | DISPLAY                                       |
|  Modules         |  [x] Minimap button                           |
|  Raid            |  [x] Guildmates in my zone on the minimap     |
|  Loot window     |  [x] Guild button opens Guild OS              |
|                  |  [x] Guild info on item tooltips              |
| OFFICER          |      [ ] Only while holding Shift             |
|  Guild rules     |  [ ] Use the game's font   [Reload to apply]  |
|  Tools & tests   |-----------------------------------------------|
|                  | STARTUP AND PRIVACY                           |
| DATA             |  [x] Login digest        [Show welcome again] |
|  Backup & reset  |  [ ] Don't name me in Discord posts           |
|  About           |                                               |
+------------------+-----------------------------------------------+
```

| Item | Sections |
|---|---|
| Profile | MY PROFILE, UI scale, DISPLAY (was GENERAL OPTIONS), STARTUP AND PRIVACY (login digest, Discord opt-out, welcome) |
| Chat & alerts | CHAT, MENTIONS & ALERTS, the LFG board notice |
| Modules | MODULES, Reload UI (from About), QUICK ACCESS |
| Raid | RAID TRACKER, unchanged |
| Loot window | opens the Loot window's Rule tab on the guild; it draws no page (the settings live there since #346) |
| Guild rules (officer) | Readiness, OFFICER RANKS, who creates events, AUTO-INVITE, !NOTE COMMAND |
| Tools & tests (officer) | MAINTENANCE, TEST FUNCTIONS |
| Backup & reset | Backup and Restore, Diagnostics, Erase guild data last, under its own rule |
| About | ABOUT & SUPPORT |

- The sidebar is built once beside the scroll frame, so it stays put while a page scrolls. Each
  refresh lays it out again for the reader: the OFFICER group and the Loot window item show to
  officers only.
- The page in sight has its sidebar label as its title. The selected item is the one gold mark on
  the sidebar: a gold label and a 2px gold rule down its left edge (selection, one of the five uses
  of gold in the Swiss 2.0 identity). The others read `textSoft`, `text` on hover; group names are
  `label` in `colHeader`.
- Labels are cut at 136px with an ellipsis, so a long translation never crosses the divider.
- `RefreshSettingsPanel(content, key)` keeps its signature. The keys of before still work:
  `general` opens Profile and `officer` opens Guild rules; an unknown key, an officer page for a
  member, or the Loot window item opens Profile.
- Nothing about a setting changes but its place. Text that named the old pages follows them:
  "Settings > General > Modules" is now "Settings > Modules"; the officer step of the first-run
  intro says "Settings -> Guild rules" and "the Loot window" (it still named Settings -> Loot from
  before #346); the mentions tip names Chat & alerts. `L["GENERAL OPTIONS"]` and `L["Officer"]`,
  which nothing reads any more, leave the locale files.
- The module descriptions and the Readiness hint end at the page's right edge instead of a fixed
  width, since the sidebar takes 164px of the window.
- Known limit: the sidebar does not scroll. An officer's list is about 342px, so a window under
  about 470px tall clips its last items.
