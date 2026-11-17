# Swiss Modernism 2.0 in the GuildOS style

Issue: danielcosta42/guildos#361. Approved by the maintainer on 2026-11-17 from the canvas
"GuildOS addon Swiss 2.0".

## 1. Goal

guildos.me moved to Swiss Modernism 2.0: one sans face, gold as the only accent and only for five
jobs, flat surfaces. The addon already uses the site's palette (`Core/Data.lua`), so this round
changes the face, three contrast failures and where gold shows up. No public name, signature or
field of `UI/Helpers.lua` changes, except three that went with the shadow and the glow:
`Helpers:CreateDropShadow`, `frame.dropShadow` and `btn.glow`. Nothing called or read them.

## 2. This change (foundations)

Everything lands in `Core/Data.lua`, `UI/Helpers.lua` and the window's title bar, before any screen.

| # | What | Before | After |
|---|---|---|---|
| 1 | Face | Spectral from 14px, Plex Mono below | IBM Plex Sans; Mono only through its roles |
| 2 | Text with no role | Mono, min 10 | Sans, min 11 |
| 3 | Roles | see `GuildOS.Fonts` | wordmark, windowTitle Sans SemiBold 18, 16; sectionTitle, itemName Sans SemiBold 14; body Sans 12; memberName Sans Medium 12; tableNum Mono 11; metricValue Mono 24; countdown Mono 40; caption, colHeader, badge unchanged |
| 4 | `lineHi` | #3a3646 (1.63:1 on bg) | #6f6878 (3.56:1), the control border at rest |
| 5 | `danger` | #cf5b52 | #ef7b72 (7.03:1 on bg) |
| 6 | New tokens | | `warn` #e89a5a, `goldHover` #e3b968, `goldActive` #c4943f |
| 7 | Removed | `shadow` | nothing reads it; `info` and its alias `blue` stay, the tank role uses them |
| 8 | Primary button | gold fill, additive glow, label drops 1px | flat gold, `goldHover`, `goldActive`; Sans Medium 12 |
| 9 | Secondary button, checkbox | `line` border, `lineHi` on hover | `lineHi` at rest, `label` on hover |
| 10 | Popup | 12px drop shadow | no shadow; `StylePopup` sets the `lineHi` border, the caller keeps the background |
| 11 | Active tab | paper label, gold rule | gold label and gold rule |
| 12 | Officer badge | the one gold-filled badge | neutral, like every other |
| 13 | Progress bar | gold while in progress; ramp ok, gold, danger | `textSoft` in progress; ramp ok, `warn`, danger |
| 14 | Metric chip | Mono 22, 34px gold rule under the value | Mono 24, gold rule on top across the chip |
| 15 | Small supporting text | `labelDim` (3.56:1 at 10px) | `label` (6.18:1) |

Ships three OFL files (`IBMPlexSans-Regular`, `-Medium`, `-SemiBold`, from IBM/plex
`@ibm/plex-sans@1.1.0`) and drops Spectral and the two `.tga` textures nothing draws any more.
`lineHi` used to double as a hover fill in three places (the two item dropdowns in
`UI/FeaturePanels.lua`, the profession filter in `UI/RecipesPanel.lua`); those move to `line` here,
because the new value is a border and would light the row. The loot priority modal
(`GuildOSPrioModal`) loses its gold frame to the `lineHi` border `StylePopup` now sets.

## 3. Unchanged

- The WoW: Forever style keeps the client's art and the game's font. The structural rules above (no
  shadow, neutral badge, progress colours) apply there too, with its own palette.
- koKR, zhCN and zhTW keep the client's font; so does the "game font" option.
- Class and quality colours, game tooltips, chat output, ChehulNet and the gold wordmark.

## 4. Next, screen by screen

135 call sites colour text gold directly (section titles, selected rows, sort arrows, values in edit
boxes, tooltip lines). Each needs a decision, so they go screen by screen in their own changes,
starting with `UI/FeaturePanels.lua` and `UI/RosterFrame.lua`. The same pass moves numeric cells
that use no role onto `tableNum`. The member card in `UI/MemberDetail.lua` keeps its gold outer ring
and top glow until its pass; until then the ring sits 2px outside the new `lineHi` border.
