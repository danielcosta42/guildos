# Forever skin: palette, fonts, art and components

Issue: danielcosta42/guildos#13 · Parent: #12 · Epic: #4

Condensed spec + plan + tasks. Design source: the Claude Design handoff for GuildOS Forever
(`design_handoff_guildos_forever/README.md` §1–5 and §8, plus the "fundações" and "componentes"
artboards of `GuildOS Forever.dc.html`).

## 1. Problem and goal

The addon wears the "Obsidian" theme: cool near-black surfaces, a desaturated violet accent and a
champagne gold. It was designed in isolation and matches neither guildos.me nor the direction of
WoW: Forever. Every existing screen should take the Forever look first — before any screen is
redesigned (#15, #16, #17) and before the one-window architecture (#14).

Decided with the maintainer (2026-09-14): gold is the only accent, so the accent colour picker goes.

## 2. Design

### 2.1 Colours: re-point, don't rewrite call sites

About 2,000 call sites read `BRutus.Colors` as `C.<key>.r, .g, .b`, mostly passed into wrappers and
locals. Re-pointing the table is the only change that reaches all of them.

`BRutus.Colors` gains the 17 handoff tokens: `bg`, `panel`, `popup`, `well`, `line`, `lineHi`, `text`,
`textSoft`, `label`, `labelDim`, `disabled`, `gold`, `onGold`, `ok`, `danger`, `info`, `epic`. The
legacy keys stay, each one a copy of the token that plays its role now:

| legacy key | uses | → token |
|---|---|---|
| `silver` | 693 | `textSoft` |
| `textDim` | 396 | `label` |
| `border`, `separator` | 327, 22 | `line` (alpha 1) |
| `accent` | 254 | `gold` |
| `accentDim` / `accentSoft` | 24 / 3 | gold × 0.54 / gold at alpha 0.14 |
| `headerBg`, `bg2`, `rowHover` | 103, 55, 73 | `panel` |
| `bg0`, `bg1`, `panelDark`, `row1` | 24, 75, 4, 32 | `well` |
| `row2` | 38 | `bg` — a faint zebra until tables get 1px separators (#15) |
| `red`, `green`, `online`, `blue`, `offline` | 131, 63, 52, 0, 15 | `danger`, `ok`, `ok`, `info`, `disabled` |
| `white` | 179 | unchanged pure white — vertex resets on icons and textures |
| `shadow` | 1 | black at 0.55 |
| `darkGold` | 0 | removed |

Name clash: the new `panel` token (#17161f, card surface) and the legacy `panel` key (window
background) share a name. The legacy key had 3 uses, all window or HUD backgrounds
(`UI/Helpers.lua` CreatePanel, `UI/RaidHUD.lua` twice); they move to `bg`.

Copies, not shared tables, so code that tweaks a colour in place can never recolour the token.

### 2.2 Accent picker removal
`BRutus.ACCENT_PRESETS`, `BRutus:ApplyTheme()`, its start-up step, the Settings swatch row and its two
locale keys go. An older `settings.theme` value stays in SavedVariables and is never read.

### 2.3 Fonts
- Four OFL files in `Media/Fonts/` with their licences: Spectral Regular and SemiBold, IBM Plex Mono
  Regular and Medium.
- `BRutus.Fonts` holds the four files (`serif`, `serifStrong`, `mono`, `monoStrong`) and the handoff
  type scale as `{ file, size }` roles:

  | role | font | px | role | font | px |
  |---|---|---|---|---|---|
  | `wordmark` | Spectral SemiBold | 18 | `caption` | IBM Plex Mono | 10 |
  | `windowTitle` | Spectral | 16 | `tableNum` | IBM Plex Mono | 12 |
  | `sectionTitle` | Spectral SemiBold | 15 | `colHeader` | IBM Plex Mono Medium | 10 |
  | `body` | Spectral | 14 | `metricValue` | IBM Plex Mono | 22 |
  | `memberName` | Spectral SemiBold | 14 | `countdown` | IBM Plex Mono | 38 |
  | `itemName` | Spectral SemiBold | 17 | `badge` | IBM Plex Mono | 10 |

  `normal` and `number` remain as mono aliases for old readers.
- `BRutus:ApplyFont(fontString, size, role)` in `Core/Data.lua` (loads before every module). A role
  wins; otherwise 14px and up is Spectral and anything smaller is IBM Plex Mono, clamped to 10px.
  Never outlined. When `SetFont` explicitly reports failure it falls back to `STANDARD_TEXT_FONT`.
- All 242 `SetFont` calls on the client font became `BRutus:ApplyFont(fs, n)`: 239 named
  `Fonts\\FRIZQT__.TTF` literally, and 3 went through a local font variable (GuildMap's `FONT`,
  Hub's `GetFont()`). A CI step keeps `FRIZQT__` from coming back.

Measured on the code before the change: of those 242 calls, 84 already had no outline, so 158 lost
theirs, and 65 asked for 7–9px. The text helpers and component labels were outlined too, so no text
keeps an outline now. Another 114 `CreateText`/`CreateHeaderText` calls and 8 calls to CorePanel's
`MakeLabel` ask for 7–9px; all 187 of those requests now render at 10px. Most sit in LootMaster,
FeaturePanels, MemberDetail, ManagementPanel and RosterFrame, so the manual pass starts there.

New font files are only seen by a client that was restarted after they were copied in — a `/reload`
is not enough the first time.

### 2.4 Art
`Media/glow-gold.tga` (128², radial white, ADD blend, tinted gold), `Media/drop-shadow.tga` (128²,
radial black at 0.55), `Media/corner-2.tga` (8², 2px radius), `Media/ring-28.tga` (32², 28px ring).
32 bpp uncompressed TGA, generated.

### 2.5 Components (`UI/Helpers.lua`)
Per the handoff state matrix: no gradient sheen (depth is surface + 1px border); primary, secondary,
ghost and danger buttons at 26px with square corners, the glow texture only behind the primary;
tab with a 2px gold rule; 14px checkbox with a solid 8px mark instead of the checkmark glyph;
8px scrollbar with a `lineHi` thumb; badge; 8px progress bar (ok ≥80%, gold ≥60%, danger below);
metric chip; drop shadow only for popups. Public names, signatures and the fields other files read
stay as they are.

Details the implementation settled:
- `CreateButton` defaults to 26px, but a caller's explicit height is kept: 222 call sites position
  buttons around their own heights, and normalising them is screen work (#15–#17).
- Buttons are secondary by default. The new `Helpers:SetButtonVariant(btn, "primary" | "secondary" |
  "ghost" | "danger")` switches them; screens opt into primary one at a time.
- `CreateTitle` is paper (window title), not gold; gold stays for the wordmark and accents.
- `CreateHeaderText` uses the `colHeader` role (IBM Plex Mono Medium) in `label`.
- `CreateDropShadow` is eight pieces of `drop-shadow.tga` around the frame, never under it, so it
  holds at any window size. `StylePopup` still does not touch backdrop colours: floating windows
  (elevation 2) and popups (elevation 4) both go through it.
- New `Helpers:CreateMetricChip(parent, value, caption, size)`, used by the home screen in #15.
- `BRutus:ApplyFont` also clamps roles: a serif role asked below 14px reads as mono, and mono roles
  never go under 10px.
- `Modules/ChehulNet.lua` keeps the client font: it is shared verbatim with other Chehul addons and
  cannot call into `BRutus`. The CI guard excludes it.
- `CreateProgressBar` fills gold while in progress and ok when complete. `ramp = true` turns on the
  ok ≥80% / gold ≥60% / danger ramp for scores that can be bad. Danger never marks progress toward a
  goal, like MemberDetail's professions and attunements.
- Two places where the handoff's text and its artboards differ, settled on the artboards: the
  checkbox mark is 8px (the state matrix says 10px; every artboard draws 8px), and a hovered primary
  button adds 0.08 to each gold channel (#edbd63) rather than compositing 8% white (#dcb05d).
- Delivered ahead of their first caller, because the screen slices build on them: `SetButtonVariant`,
  `CreateMetricChip`, the badge rules, `corner-2.tga` and `ring-28.tga` (#14, #15).
- Fixes from the review that touched screens: ASCII "+"/"-" expand marks (IBM Plex Mono has no ▶ or
  ▼); the popup surface for the two item dropdowns and the ally card, with a visible hover; no
  hard-coded Obsidian violet left, in decimals or as hex (the digest's alliance line is gold now, and
  alliance feed events are label); a dark chip behind the talent rank and the minimap "+N"; a wider
  wishlist position column; WebPanel buttons no longer dimmed twice when disabled; taller talent tabs.

## 3. Out of scope
Screen layouts, column drop orders and row separators (#15–#17); the single window and the resize
ladder (#14); the minimap "G" wordmark (#17).

## 4. Tests
- `tools/forever-skin.lua` (luajit, real `Core/Data.lua`): every token has the handoff hex; every
  legacy key resolves to its token; nothing but `epic` is violet; legacy keys are copies; the picker
  is gone; `ApplyFont` picks the family by size, clamps to 10, never outlines, honours roles and
  falls back only on explicit failure; each role matches the type scale above; the four fonts and
  four textures exist with the right sizes.
- `tools/forever-components.lua` (luajit, the real `UI/Helpers.lua` under a stub frame API): rest,
  hover, pressed and disabled for the four button variants and the checkbox; rest, hover, pressed,
  released and active for the tab; rest, hover and leave for the close button; the fills, borders,
  text colours and sizes of badges, the scrollbar, icons, the progress bar and the metric chip; the
  glow's reach and layer, the drop shadow's pieces and 12px reach, the 0.1s fade cap; plus the
  contracts older screens rely on (a caller's button height, `SetBaseColor` during hover,
  `checkbox.onChanged`).
- Mutation check: 108 hand-written mutants of `Core/Data.lua`, `UI/Helpers.lua` and the screens
  (tokens, aliases, font rules and files, the component states and sizes listed above, the violet
  scan in decimals and hex); the two harnesses kill all 108.
- `tools/startup-isolation.lua`, `tools/roster-import.lua` and `tools/attendance-parity.lua` still
  pass. `tools/companion-payload.lua` fails at `Modules/CompanionExport.lua:144` exactly as it does
  at `HEAD` — pre-existing, not this change. `luacheck` clean.
- Manual on Anniversary (needs the game, after a client restart): screenshots of roster, raids,
  loot master, member detail, settings and one popup on the issue. Known to look at: the three
  Loot Master settings hints (minimum attendance, disenchanter, rarity threshold) now wrap to two
  lines inside their fixed widths.

## 5. Tasks
- [x] Tokens, legacy aliases and `ApplyFont` in `Core/Data.lua`; picker removed
- [x] Fonts, licences and textures in `Media/`
- [x] Font call sites through `ApplyFont` (242); CI guard against `FRIZQT__`
- [x] Components in `UI/Helpers.lua`; legacy `panel` uses moved to `bg`
- [x] `tools/forever-skin.lua` (348 checks; the violet scan adds one per file in the TOC) and
  `tools/forever-components.lua` (138 checks; #14 added 4 for sub-tabs, 142 now)
- [x] Docs: ADR-0013, functions catalog, Media README
- [ ] Manual check with screenshots on Anniversary
