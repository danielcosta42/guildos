# UI styles: a WoW: Forever style from the client's own art

Issue: danielcosta42/guildos#119 (epic). Decided with the maintainer on 2026-10-07.

## 1. Problem and goal

Players asked for selectable UI styles, the way EllesmereUI offers "EllesmereUI Style", "WoW Forever",
"Blizzard Style" and "Classic WoW UI". GuildOS has one look, a flat dark skin from the 2026-09 design
handoff (`2026-09-14-forever-skin-design.md`). It was designed to match guildos.me, not the game.

The goal is that a player on WoW: Forever can open GuildOS and have it look like part of the game,
while anyone who prefers today's look keeps it.

Decided:

- **Styles.** There are two styles in this epic: today's look stays the default, and a WoW: Forever style
  is added. The picker is built to take more later; a Blizzard or Classic style is out of scope here.
- **The Forever style.**
  - It is built from the Forever client's own art: the `-c60` texture atlases (1,916 of them in
    1.60.1.70235) that Anniversary does not have.
  - Nothing of Blizzard's is copied into the addon.
  - The style is offered only where the client has the art.
- **Scope.** It covers the whole UI, screen by screen, not only the frame. Delivery is in phases.
- **BRutus goes.** Every trace of the old "BRutus" name goes first (phase 0): the global alias, the
  `BRutusDB` saved variable and its migration, and the `/brutus` and `/br` commands.

## 2. Names

The current skin is called "Forever skin" in code comments and in the 2026-09 spec. That name came
from the design handoff, not from the game, and it would collide with the new style. From phase 1 on:

| id | shown as | what it is |
|---|---|---|
| `guildos` | GuildOS | today's flat look; the default |
| `forever` | WoW: Forever | the Forever client's art |

The comments that say "Forever skin" for today's look are renamed in phase 1.

## 3. Phase 0: BRutus out of the addon

`_G.BRutus` is an alias of `_G.GuildOS` (Core/Core.lua:10), and 5,830 references in 160 Lua files still
use it.

- **The global.**
  - Every `BRutus` in code becomes `GuildOS`, and the alias line goes.
  - `.luacheckrc`, the CI workflow, `.local-memory`, `.memory`, `.cursorrules`, the Copilot
    instructions, docs and the harnesses in `tools/` follow.
  - File headers that still say "BRutus Guild Manager" are rewritten.
- **`BRutusDB`.**
  - It leaves the TOC's `## SavedVariables`.
  - The one-time copy into `GuildOSDB` (Core/Core.lua, about lines 126-139) and
    `GuildOS.LEGACY_DB_GLOBAL` go.
  - The reset command stops touching it (Core/Commands.lua:290).
  - The migration has run for everyone who opened the addon in the last months. Anyone who skipped
    from a much older version straight to this one would lose what was only in `BRutusDB`. The
    maintainer accepted that.
- **Commands.** `SLASH_BRUTUS1/2` (`/brutus`, `/br`) and `GuildOS.SLASH_LEGACY` go. Only `/guildos` and
  `/gos` remain.
- **GuildOS_Demo.** The dev addon outside the repo stubs `BRutus` and is updated alongside.
- **The guard.** A harness, `tools/no-brutus.lua`, fails if `brutus`, in any case, appears in a file git tracks,
  except `CHANGELOG.md` (the release history), `Libs/` (third party), the dated specs and plans under
  `docs/superpowers/` (records of what was, this spec included) and the guard itself. It also checks
  that `Bindings.xml` calls a `GuildOS:` method that exists, and that the Loot Master's prefix is one
  constant, `"GuildOSLM"`.

Phase 0 is a mechanical rename with no behaviour change beyond the three removals above. It is its own
issue and PR, before phase 1, so the style code is written with the new name.

## 4. Phase 1: the style layer, the frame, the components, the picker

### 4.1 Core/Style.lua

A registry of styles, loaded after `Core/Data.lua` (which defines `GuildOS.Colors` and `GuildOS.Fonts`)
and before every `UI/` file.

```
GuildOS.Style:Available()      -> { "guildos", "forever"? } in display order
GuildOS.Style:Current()        -> the id in use this session
GuildOS.Style:Choose(id)       -> saves GuildOSDB.style; takes effect after a reload
GuildOS.Style:Paint(frame, role, opts)
GuildOS.Style:Skin<Control>(widget, ...)   -- Button, Tab, SubTabBar, Checkbox, ScrollBar, Close, TitleBar
```

- **Where the choice lives.** It is saved at the account root, in `GuildOSDB.style`, the way
  `GuildOSDB.font` is (#57). It is a display preference, not guild data.
- **When `forever` is available.** Only when the client answers `C_Texture.GetAtlasInfo` for the
  style's key atlases. This is checked at run time, not by `Client.isAnniversary`, so a patch that
  renames or drops the art hides the style instead of drawing holes.
- **Resolving at load.** On `ADDON_LOADED`, `Current()` resolves to the saved style if it is available,
  else to `guildos`. When a saved `forever` falls back, the player is told once in chat why.

### 4.2 Re-pointing colours and fonts at load

About 2,000 call sites read `GuildOS.Colors` as `C.<key>.r/g/b`, and every FontString goes through
`ApplyFont`. A style changes both in place, on `ADDON_LOADED`, before any window is built (the UI is
built the first time it opens):

- **Colours.** The Forever style re-points the tokens (`bg`, `panel`, `well`, `line`, `text`,
  `textSoft`, `label`, `gold`, …) to a palette that sits on the client's art: stone and bronze surfaces,
  parchment text, and the game's yellow (1, 0.82, 0) as the accent. The legacy aliases follow their
  tokens as they do today.
- **Fonts.** The Forever style uses the game's font for every role, through the same path
  `GuildOSDB.font == "game"` and `GameFontOnly` already take.
- **Values copied at load.** A constant copied out of `Colors` at file load does not follow (for
  example `SHADOW_ALPHA = C.shadow.a` in Helpers). Phase 1 lists and fixes each one; the harness
  checks a second style's palette reaches a module that captured `C` at load.

### 4.3 Painting by role

`Style:Paint(frame, role)` replaces direct backdrop painting. The roles:

| role | what it is | `guildos` (today, unchanged) | `forever` (candidates) |
|---|---|---|---|
| `window` | the main window and standalone frames | `bg` with a 1px `line` | metal nine-slice `ui-frame-metal-*-c60-2x` |
| `titlebar` | a window's title bar | `panel` | `ui-frame-diamondmetal-header-tile-c60-2x` |
| `panel` / `card` | a block inside a screen | `panel` / `well` with a 1px `line` | `heavybronze-frame-basic-c60` + `heavybronze-*-cornerbracket-*-c60` |
| `well` | an inset: a list, a table body, a scroll area | `well` | `common-insideframe-c60` |
| `row` | a list or table row, with zebra and hover | `row1` / `row2` / `rowHover` | the `well` art with a palette tint |
| `input` | an edit box | `well` with a 1px `line` | `common-search-border-left/middle/right-c60` |
| `popup` / `tooltip` | a popup, a dialog, the addon's tooltips | `popup` + drop shadow | `tooltip-nineslice-*-c60` |

**Naming, measured in game (2026-10-07, build 1.60.1.70245):** an addon asks for the atlas *element* (`UI-Frame-Metal-CornerTopLeft`, `128-RedButton-Left`, `common-internaltab`). Forever resolves an element to its `-c60` member through the active atlas set. The member names in the tables above are what the art is called in the data, but `GetAtlasInfo` answers nil for them. `Core/Style.lua` uses element names, and `tools/data/forever-atlas-elements.txt` lists the ones Forever draws with `-c60` art. The tooltip's `-c60` centre is not in that set, so the popup has no centre texture.

The controls, through the Helpers that already build them:

| control | `forever` (candidates) |
|---|---|
| tab and sub-tab | `common-internaltab-c60`, `-hover-c60`, `-selected-c60` |
| close | `redbutton-exit-c60` (+ `-pressed-c60`, `-disabled-c60`) |
| scroll bar | `minimal-scrollbar-*-c60` |
| checkbox | `checkbox-minimal-c60` with `talents-checkmark-c60` |
| button (primary, secondary, danger; ghost has no art) | the retail panel button, three-slice: `128-redbutton-left-c60`, `_128-redbutton-center-c60`, `128-redbutton-right-c60`, with `-pressed` and `-disabled` (found in the client's data; the square `128-redbutton-exit/minus-c60` are the close and minimise buttons) |

- **Candidates, not final.** These atlases exist in the client's data, but how they look on screen has
  not been seen. The final pick of each piece is made from beta screenshots of the preview tool (4.6).
- **The `guildos` style moves, unchanged.** Its implementation is today's Helpers drawing code, moved
  into the style without a visual change.
- **The API holds.** `CreatePanel`, `CreateDarkPanel`, `CreateButton`, `SetButtonVariant`,
  `CreateTab`, `StyleSubTabBar`, `CreateCheckbox`, `CreateCloseButton`, `SkinScrollBar`,
  `TitleBarButton` and `StylePopup` keep their names, signatures and returned fields, and delegate the
  drawing to the style. No screen changes in phase 1.

### 4.4 What phase 1 changes on screen

In the Forever style:

- **The frame and components.** The main window's frame and title bar, every tab and sub-tab, button,
  checkbox, scroll bar, close button and popup built through the Helpers.
- **Every colour and font.** The screens that still paint their own backdrops (section 5) do not get
  the art yet, but they take the new palette and font, so they do not clash.

The `guildos` style looks exactly as today.

### 4.5 The picker

- **Where it is.** Settings, next to "Use the game's font": an "Interface style" row of cards, one per
  available style. Each card has the style's name, one line of description, and "In use" or "Apply".
- **Apply.** It saves through `Style:Choose` and asks "Reload the interface now?" (Reload / Later).
  There is no live switch: frames are built once, and a half-switched window is worse than a reload.
- **Interaction with the game font.** While the Forever style is in use, "Use the game's font" shows
  as on and disabled, as it does on Korean and Chinese clients (#103).
- **Commands.** `/gos style` lists the styles and marks the one in use. `/gos style <id>` chooses one
  and asks for the reload. An unknown or unavailable id says which ones exist.

### 4.6 The preview tool

`/gos style preview` opens a frame with the candidates for each role and control side by side, each
labelled with its atlas name, and with any atlas the client does not have marked missing. It is how the
pieces are chosen from beta screenshots, and it stays afterwards as a diagnostic, listed under
`/gos help` in the debug group.

## 5. Phases 2+: the screens

Each phase takes the screens of one tab and turns every direct backdrop and `WHITE8x8` fill into a
`Style:Paint` role or a Helpers control. There is one PR per phase, each checked in the beta before
the next.

These counts are direct `SetBackdrop(` / `WHITE8x8` uses on 2026-10-07; a few are 1px rules and accent
lines that stay solid fills.

| phase | tab(s) | files (direct paints) |
|---|---|---|
| 2 | Now, Roster | Agora (1), RosterFrame (27), MemberDetail (25) |
| 3 | Raids, DKP, Wishlist | CorePanel (8), RaidToolsPanel (2), RaiderPanel (2), PointsPanel (3), CalendarPanel (4), RaidHUD (7), PugInspector (3) |
| 4 | Loot | LootMaster (32) |
| 5 | Professions | ProfessionsPanel (4), RecipesPanel (7), CraftFinder (7) |
| 6 | Guild, Alliance | CommunityPanel (2), GuildMap (3), AlliancePanel (12), Polls (3), Bulletin (2), CallToArms (1) |
| 7 | Recruitment, Trials | RecruitBeacon (6), RecruitmentSystem (4), RecruitScanner (1), LFGBoard (1) |
| 8 | Leadership, Web, Settings, the rest | FeaturePanels (67), ManagementPanel (6), AuditPanel (2), WebPanel (4), GuildAnalytics (3), Search (2), Backup (2), Digest (1), Utils (4), Window (2) |

## 6. Errors

- **A saved style that is no longer available.** For example, the Forever art is gone after a patch, or
  the account is now on Anniversary. The addon falls back to `guildos` and says so in chat once per
  session.
- **An atlas missing for one piece.** That piece is painted the `guildos` way, and the missing atlas is
  recorded once in `/gos errors`. The window always opens.
- **The guard.** `Style:Paint` and the `Skin*` calls never raise into a screen's build. A failing piece
  degrades to the flat paint.

## 7. Tests

- **`tools/no-brutus.lua` (phase 0).** No `brutus`, in any case, in a tracked file outside the exceptions
  of §3. The TOC has no `BRutusDB`. `/brutus` and `/br` are not registered.
- **`tools/style.lua` (phase 1):**
  - `Available()` offers `forever` with the key atlases, and only `guildos` without them;
  - `Choose` saves to `GuildOSDB.style`;
  - a saved style that is unavailable, or unknown, falls back to `guildos` and says so once;
  - choosing `forever` re-points `Colors` and `Fonts` in place, and a module that captured `local C` at
    load sees the new palette;
  - `Paint` for every role in both styles: `guildos` makes the same backdrop calls as today; `forever`
    uses the role's atlases; a missing atlas falls back without raising and is recorded once;
  - the picker shows only the available styles, and "Apply" saves and asks to reload;
  - `/gos style` lists, chooses, and refuses an unknown id;
  - `/gos style preview` builds with every candidate and marks the missing ones.
- **Both styles through the existing harnesses.** `tools/window-shell.lua` and the Helpers-based
  harnesses run under both styles with the same layout checks, which proves the Helpers API did not
  change.
- **Mutants** on each rule above, as for every change.
- **The beta.** Each phase is checked with screenshots, since a harness does not see the art.

## 8. Out of scope

- A Blizzard or Classic style, and any style beyond the two.
- A live style switch without a reload.
- The site (guildos.me).
- Re-designing any screen's layout. The phases change how a screen is painted, not what is on it.
