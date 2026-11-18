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

### 4.1 `UI/FeaturePanels.lua` and `UI/RosterFrame.lua` (issue #363)

Text only: gold fills, borders, rules, washes and textures in these files stay for a later pass.
Line numbers are those of d54a075. FP is `UI/FeaturePanels.lua`, RF is `UI/RosterFrame.lua`.

| Sites | What | Decision |
|---|---|---|
| FP 106, 1341, 1406, 1481, 2836, 3449; RF 2860 | Core card name, popup titles (Export, Import SoftRes, Raid roster, MY WISHLIST, MANAGE PRIORITIES), Recruitment section headers | `text`, `sectionTitle` |
| FP 696, 774, 2870, 3618; RF 729 | Column headers (RF 729 repainted the roster header gold on mouse-out) | `label`, `colHeader`, as `UI:CreateHeaderText` |
| FP 1623, 3062; RF 820 | Selected Settings category, off-spec radio, rail segment | keep gold (selection) |
| FP 525, 586, 1044 | Expand marks `+`, `-`, `>` | `label` |
| FP 114 | "request sent" on a core card | `textSoft` (in progress, as the progress bar) |
| FP 715, 819, 832, 1090; RF 253, 288 | Middle step of the green, gold, red ramps (score, attendance, average score, trial days left) | `warn`, as the progress bar ramp |
| FP 848 | "missed last raid" (one miss; two or more stay `danger`) | `warn` |
| FP 1100 | TRIAL status (APPROVED stays `ok`, DENIED and EXPIRED stay `danger`) | `textSoft` (in progress) |
| FP 1175 | "Comments:" label in a trial's detail | `label` |
| FP 922, 2135, 2409; RF 3287 | Values in edit boxes (trial length, penalty, minimum item level; the guild's Discord) | `text`; the three numeric ones on `tableNum` |
| FP 2728 | Version line in About | `text` |
| FP 3653 | `#` order in the priority modal | `text`, `tableNum` |
| FP 443, 3809 | Inline gold on the current raid group and on the item name in the priority modal | drop the colour code (`text`) |
| FP 529, 543 | 25-man raid name; session count (`accentDim`) | `text` (10-man stays `textSoft`); `label` |
| FP 861, 3087, 3099; RF 1974, 1978, 2009, 2015, 2043, 2081 | Tooltip lines: attendance heading, Main Spec, Off Spec, rank, earned titles, average item level, Professions, Attunements, Wishlist | `text` |
| RF 2017 | Primary profession in the member tooltip (secondary stays `textSoft`) | `text` |
| RF 2054 | Attunement in progress in the tooltip (done `ok`, not started `danger`) | `textSoft` |
| RF 2071 | A newer Guild OS version in the tooltip (older stays `danger`) | `label` |
| RF 706 | Sort arrow | `text` |
| RF 243, 268, 272, 1604 | Roster cells: M+ rating with no game colour, core, DKP, primary professions | `text` |
| RF 2344, 2448, 2525 | Priority stars and badges (`*`, `* #N`), whose inline gold code overrode the colour | drop the code; `text`; the `* #N` ones on `tableNum` |
| RF 2650 | The guild's Discord link in Recruitment | `text` |
| RF 532, 534 | Average item level and "with Guild OS" metric values | `text` (the gold belongs to the metric rule) |
| RF 790, 914, 2500 | Rail labels VIEW, RANKS, CLASSES; "OFFICIAL PRIORITY (N)" in the wishlist detail | `label`, `colHeader` (maintainer, 2026-11-17) |
| RF 1575 | Level at the cap in the roster table (ten below it stays `ok`, the rest stay `white`) | `text` (maintainer, 2026-11-17) |
| FP 2733 | Inline gold on "Chehul" in the About credit | drop the code; the line stays `textSoft` (maintainer, 2026-11-17) |

Unchanged: chat output (FP 2226), per §3; the gold wash on a trial row waiting for review
(FP 1040), which is a background; and the amber Demote and Mark as Trial entries of the member
context menu (RF 1861, 1926), whose colour codes sit inside locale strings in every translation and
go with a locale pass. The "game tooltips" of §3 are the game's own frames and item tooltips; lines
the addon adds to them follow the table above. The maintainer also chose a `text` label for the old
"Sign Up" button, but main has since replaced that row with the core card, whose action is a
standard button.

Numeric cells with no role move to `tableNum` (Plex Mono 11). A cell is numeric when its value is a
number, a percentage, a fraction, a date, a time or a duration, with at most a unit (`%`, `d`, `pts`);
a count followed by a word ("12 players", "3 kills") and a relative time ("3 days ago") stay Sans.

- FP: week range, session date and duration, player score and consumables, attendance %, raids,
  average score, last raid, trial item level, attunement and days left, wishlist order, the priority
  modal's two order columns.
- RF: level and item level; the optional columns that set `num` (addon version, missing enchants,
  M+, attendance, DKP, loot received, trial days); attendance %, wishlist order and priority `* #N`
  in the wishlist view. The official priority's `* #N` is Mono 10, not 11, so `* #12` fits its 32px
  column before the item name.
