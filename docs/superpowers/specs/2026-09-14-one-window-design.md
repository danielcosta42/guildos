# One window: shell, tab bar and the resize ladder

Issue: danielcosta42/guildos#14 · Parent: #12 · Epic: #4 · Depends on #13 (skin), #6, #7 · ADR-0016

Condensed spec + plan + tasks.

## 1. Problem

Three containers did overlapping jobs:
- the hub (`UI/Hub.lua`): a 430px card, no resize;
- one floating window per feature (`UI/Window.lua`): resizable and persisted;
- the expanded frame (`UI/RosterFrame.lua`): 1236×844, every feature as a tab, no resize, nothing persisted.

Entry points opened different ones: `/gos` and the minimap click the hub, `/gos open` a window, the dashboard the
expanded frame's tabs. The Leadership deep links the hub sent (`inactive`, `suggest`) were silently ignored:
`ManagementPanel` never exposed its `selectSub`.

The handoff (§6) replaces all three with one resizable window that reorganises by width. Its first tab, `agora`,
is the live column.

## 2. Design

### 2.1 The window
- **One frame:** `BRutus.RosterFrame`, frame name `GuildOSWindow`, built in `UI/Window.lua` the first time anything
  opens it. Every registry feature with `tab` is a tab. A panel builds the first time its tab opens
  (`RunStartup("Tab:<id>")`), and one that raised stays refused until `/reload`.
- **Size:** 1000×620 by default, resize bounds 320×28, a 16×16 grip in the bottom-right corner, strata HIGH.
  `uiScale` applies (`UI:ApplyScale`).
- **Persistence:** `settings.window` holds `left`, `top`, `w`, `h` (frame coordinates of the top-left corner), the
  open tab and the fold (`collapsed`, `restoreW`, `restoreH`).
  - Saved when the title bar drag or the grip lets go, on minimise and restore, and for every tab the player opens.
  - On creation: nothing saved → 1000×620, centred, capped to the scaled screen. Saved → `UI:ClampWindowRect`
    pulls it onto the current screen, never larger than the screen and never smaller than the bar.
- **Title bar:** 30px, 28px under 620px width, on `panel` with a 1px `line` below.
  - Left: the gold wordmark "GuildOS" (`wordmark` role) and a `caption` line in `labelDim`: guild · N online. While
    the roster has not arrived, a dash replaces the count.
  - Right: the sync time in `label` ("sync 4m ago", from the newest `db.members[*].lastSync`; "not synced yet"
    before any), minimise "—" and close "×" (the skin's close button).
  - The issue asks for the sync time here. The handoff's "raide em 4h12" lives in Now and in the bar.
- **Content:** padding 12px, 8px under 620px; clipped, so a panel not yet redesigned for a narrow band is cut at
  the window's edge instead of painting past it.
- **Footer:** 22px, 1px `line` above.
  - Ghost actions Search, Sync, Core Sign-up and Blizzard, plus the invite field for whoever `CanGuildInvite`.
  - They drop lowest priority first through `UI:ResolveColumns`: Blizzard, Core Sign-up, invite, Sync, Search.
  - Core Sign-up had no other way in once the old bottom bar went. The old bar's Wishlist and DKP buttons are not
    repeated: both have their own entry points.
- **Refresh:**
  - The title refreshes on a 10s ticker while shown, on `GUILD_ROSTER_UPDATE`, and when the band changes. A resize
    within a band does not refresh it.
  - The refresh is guarded (`SafeCall`), and it builds the bar's three numbers only in the bar band.
  - Group, raid and loot-method events re-check the tabs.
  - Hidden, the window runs no timer.

### 2.2 One way in
- **`UI:OpenWindow(id, sub, filter)`**, in this order:
  - refuses an unknown id or a background module;
  - says "disabled in Settings", "could not start on this client" or "officer-only";
  - shows the window, and unfolds it when the saved fold says so (or it is in the bar band), laying it out at once.
    The saved fold decides because right after `/reload` the band is not known yet;
  - opens the tab (remembered);
  - passes `sub` and `filter` to the panel's `SelectSub`.
- **`UI:ToggleMain()`** shows or hides the window on the remembered tab.
- **Callers:**
  - `/gos` and unknown verbs, through `BRutus:ToggleRoster`, which keeps sending a guildless player to the
    recruitment finder;
  - `/gos open <id> [sub]`, `/gos banlist` (now on the ban sub-tab) and `/gos calendar`;
  - the minimap click and its menu (the window's tabs);
  - the guild-frame takeover and its "Guild OS" button;
  - the digest, onboarding and the home cards;
  - a new key binding, "Open or close Guild OS" (`Bindings.xml`, category AddOns, unbound by default).
- **Sub-tabs and filters:**
  - Raids, Guild and Alliance already exposed `SelectSub`. Leadership, Audit, Raid Tools and Recruitment now do,
    which fixes the hub's dropped deep links.
  - The Guild tab hands a deep link's `filter` to the sub-panel's `ApplyFilter`; the calendar's selects the day of
    a timestamp.
- **Removed:**
  - `UI/Hub.lua`;
  - the per-feature windows: `UI:CreateWindow`, `ToggleWindow`, `IsWindowOpen`, `GetWindow`, `CloseAllWindows`,
    `RaiseWindow` and their self-tests;
  - `BRutus:ToggleExpanded` and `BRutus.CreateRosterFrame`;
  - the registry's `hub`, `w`, `h`, `minW`, `minH`, `resizable` and `icon`;
  - the Settings "live info on the hub" checkbox, and the 15 locale keys only the hub and the old help lines read.
- `IsFrontDoorShown`, `HideFrontDoor` and `RefreshRosterUI` read the one window. Nothing reaches for a frame by
  its global name.

### 2.3 Tab rule and sub-tabs
- **Rule:** 28px, 1px `line` below. Tabs are `UI:CreateTab` (mono 11, a 2px gold rule under the open one), as wide
  as their label plus 20px (48px at least), 2px apart, from 6px in.
- **Overflow:** `UI:FitTabs(widths, width − 12, 2, 36, active)` decides what fits.
  - The rest fold into a ghost "»n" at the right edge, which opens a menu of those tabs.
  - The open tab always stays on the rule; a tab never becomes an icon.
- **Which tabs:** `UI:IsFeatureAllowed`, per tab and live. There is no tab for a feature this client does not
  support (#7), whose module failed to start (#6), that is switched off, or that the player's rank or loot system
  does not allow. When the open tab stops being allowed, the window falls back to Now.
- **Sub-tabs:** `UI:CreateTab(parent, text, width, true)` draws a 1px rule, and `UI:StyleSubTabBar(bar)` puts the
  bar on `panel`.
  - Applied to Raids, Leadership, Audit, Raid Tools, Guild, Alliance and Recruitment.
  - Every sub-tab bar is 28px now; Raids, Audit, Raid Tools and Guild were 26px.

### 2.4 The resize ladder (handoff §6)
`UI.LADDER` and `UI:ResolveBand(width, current)` in `UI/Layout.lua`. A band changes only once the width is 16px past
its line, in either direction. The window re-reads its band on every size change (coalesced per frame by
`MakeResponsive`), and nothing animates.

| width | band (key) | what changes |
|---|---|---|
| 1000 → 880 | pleno (`full`) | 10 tabs · every roster column · home in two columns |
| 880 → 780 | cheio (`wide`) | the note column goes |
| 780 → 700 | confortável (`medium`) | "visto" goes · tabs 6 + »4 · home stacks |
| 700 → 600 | estreito (`compact`) | rank becomes a badge · tabs 4 + »6 |
| 600 → 520 | mínimo de tabela (`narrow`) | presence dot before the name · toolbar "filtros · n" |
| 520 → 420 | vigia (`watch`) | the tab rule becomes a one-line selector · content switches to `agora` |
| 420 → 320 | barra (`bar`) | only the 28px title bar: online · time to raid · pending |

- **Measured on the panel hosting the table:** the content area, the window less its padding (12px a side, 8px
  under 620px), not the window.
  - At 1000px the content is 976px, so the band is full.
  - An 887px window has 863px of content, so it is wide, while an 890px one (866px) stays full.
- **The rule:** from `full` to `narrow` the rule shows the tabs that fit. The handoff's tab counts are for its ten
  tabs; `FitTabs` counts the real labels.
- **Watch:**
  - A one-line ghost selector naming the open tab ("Now »") replaces the rule; it opens a menu of every tab, the
    open one checked.
  - The content switches to Now. The tab that was open comes back when the window widens, unless the player picked
    another meanwhile. The switch is not remembered as a choice.
  - A Now tab that failed to build is not retried each time.
- **Bar:**
  - Only the 28px title bar: the wordmark, then `UI.Agora:BarText()`: online · time to the next raid ("4h12", a
    dash when none) · what needs me (gold above zero), with dashes for the two counts while the roster loads.
    Then "+" and "×", the close button clear of the grip.
  - Letting go of the grip in this band, or pressing "—" anywhere, folds the window to 28px and keeps its size.
  - "+" or `UI:OpenWindow` restores that size, never narrower than 452px, so the content (436px) lands past the band.
  - A folded window dragged wider unfolds only once its content clears the band.
- **Not #14:** the column drops inside tables (note, visto, rank badge, presence dot, "filtros · n"). Each panel
  measures its own width for them, in #15–#17.

### 2.5 Now (`agora`)
- **The tab:** it keeps the id `home` (saved settings and the fall-back already use it) and is labelled Now
  ("Agora"). It replaces the hub's live column.
- **Layout:** a 296px column. From 780px of tab width the existing home cards (`UI/Dashboard.lua`) build once and
  sit beside it; under 780px the column fills the tab. #15 redesigns the home screen.
- **Next raid card:**
  - the countdown in gold (`countdown` role at 19px: "4:12:38", or "2d 4h" from a day out);
  - the title, day and time, and how many are going;
  - a primary "Open calendar" button that opens Guild › Calendar on the raid's day, hidden when that tab is not
    allowed.
  - The next raid is the first future calendar event of kind RAID. Events made before kinds existed count as raids.
    Nothing is read until Calendar has started.
- **Needs me card:** 26px rows with a 6×6 mark (danger when urgent, gold otherwise), urgent first, at most five.
  Only items whose screen the player can open.
  - Trials with less than a day left: `TrialTracker` counts whole days rounded down, so 0. Urgent; opens Trials.
  - An unanswered raid within the week: Guild › Calendar, on the raid's day.
  - Officers also get inactive members (Leadership › Inactivity), "N promotions to review" (Leadership ›
    Suggestions; its ready trials are the ones the trials row already counts) and applicants waiting
    (Recruitment › Scanner).
- **Activity card:** the rest of the column. The last 48 hours, newest first, as many rows as fit (at most 12),
  with a 44px time before the text.
  - Roster log joins, leaves, removals, promotions and demotions: Leadership › Audit Log, plus that member's
    detail when exactly one saved member has the name, looked up only for the rows kept. The log has no search
    of its own.
  - Loot awards: Loot, plus the detail of the member who got the item.
  - Level and attunement milestones: the roster, plus the member.
  - Raids tracked: Raids › Sessions, timed at their end, since `RaidTracker` saves a session when it ends.
  - When the owning screen is officer-only and the player is not an officer, the row opens the roster.
- **Every row is a button:** `UI:OpenWindow(id, sub, filter)`, then the member detail when the row names a member.
  - The filter is the sub-tab, the calendar's day or the member, where the owning screen has one.
  - Trials, the loot list and the raid sessions have no narrower filter yet, so their rows open the screen or
    sub-tab.
- **States:**
  - Nothing to show: one line that is not a button ("All caught up", "Nothing in the last 48 hours.",
    "No raid scheduled.").
  - Roster not in yet (in a guild, zero members): three static bars in Needs me, and dashes for the counts in the
    title and the bar.
- **Refresh:**
  - Data is fetched on show, on every tenth tick of the 1s clock, and on `GUILD_ROSTER_UPDATE`.
  - A resize only repaints what was fetched, because the officer work walks the whole roster.
  - Each fetch is guarded (`SafeCall`). Off screen it runs nothing.
- **Not provided by any code today (follow-ups):**
  - unowned loot ("loots sem dono");
  - a seen marker for applications ("novas");
  - timestamped absence, wishlist and recipe events;
  - points changes grouped into one row, trial progress and alliance joins in the feed;
  - who has not answered a raid ("sem resposta");
  - a raid in progress in the feed;
  - a real last-sync time;
  - narrower filters on Trials, the loot list and the raid sessions.
- **Dropped from the hub:** its "YOU" line (DKP, attendance, wishlist count); the home cards, the DKP tab and the
  wishlist cover it.

## 3. Tests
- `tools/window-shell.lua` (luajit; 293 checks). It runs the real `Core/Core.lua`, `Compat.lua`, `Data.lua` and
  `Commands.lua`, and the real `UI/Helpers.lua`, `Layout.lua`, `FeatureRegistry.lua`, `Window.lua`, `Agora.lua`,
  `CalendarPanel.lua`, `CommunityPanel.lua`, `Minimap.lua` and `Features.lua`. The frame API is stubbed, and the stub fires OnShow,
  OnHide and OnSizeChanged and records resize bounds and clipping. It covers:
  - **Entry points, run for real:**
    - `/gos` (guildless too) and the shared `/brutus` handler;
    - the minimap button's left and right click and its menu;
    - the guild-key hook both ways, and the "Guild OS" button on Blizzard's frame;
    - `/gos open`, `/gos banlist` and `/gos calendar`, including the usage message;
    - the key binding's label and category, the digest and onboarding calls, and `RefreshRosterUI`.
  - **Which features get a tab:** available, unsupported, disabled (and back), failed to start, officer-only for a
    member, a panel that raises (recorded as `Tab:<id>`), and the open tab's feature switched off.
  - **Geometry:**
    - a movable, resizable window on the HIGH strata: the title bar's drag moves it, and the grip sizes it from its
      corner;
    - resize bounds, grip size, clipping, the clamp cases;
    - save on drag stop, grip release, minimise and restore;
    - restore after `/reload` with the open tab; off-screen, scale.
  - **Title bar, footer and refresh:**
    - the gold Spectral wordmark "GuildOS" on `panel`, over a 1px line; mono 11 tab labels over a 1px line;
    - "×" closing the window;
    - meta in `labelDim` and the loading dash; sync time in `label`; close position; padding at 1000 and 600px;
    - the 10s ticker and the three events, and no title refresh while the window is closed;
    - ghost footer actions by priority from a 10px inset under a 1px line; each runs what it names; invite only for
      who can, asking for a name when empty and clearing after it invites.
  - **Rule:** Now first, and core; every tab placed in order and named at 1000px; a click opening, marking and
    remembering a tab; hysteresis on the content width at 890/887px; the
    30px title bar, 12px padding and narrow band at exactly 620px; a ghost "»n" at
    the right edge, its count, `FitTabs` agreement, menu entries, a folded tab opening and staying on the rule.
  - **Watch:** Now, the ghost selector, not remembered, the menu, coming back wide, a pick from the selector.
  - **Bar:**
    - folding on grip release, saved; the three numbers; close clear of the grip; restore laid out at once;
    - minimise, saved; the title refreshed the moment it unfolds;
    - folded after `/reload`, then a deep link unfolding it before the next frame;
    - dragging out; a drag to 440px staying folded and still opening back to its old size; landing past the band.
  - **Now's data:**
    - next raid, and no calendar yet; clock and short form;
    - needs: order, a trial with a whole day left, a week ±1s, the calendar filter, promotions only in the
      suggestions row, closed screens, a member;
    - activity: all five roster actions, member keys including an ambiguous name, loot with its member, both
      milestone kinds, a tracked raid at its end, 47h in and 49h out (roster and loot), at most 12, the member
      fallback;
    - bar text with dashes while loading.
  - **Now's column:**
    - home cards 8px beside the column at 976px and at exactly 780px, gone at 779px and 700px (built once); the
      cards stacked 8px apart, activity to the column's bottom; the gold mono countdown and meta; the primary
      calendar button on the raid's day, hidden without the Guild tab;
    - 26px rows stacked inside the list's frame, 6px marks, text clear of the mark and of the 44px time, the
      time up to a day and the weekday past it; rows fitting the height, and never more than 12;
    - hover only on rows that open something;
    - a resize that does not refetch; the tenth tick and a roster event refreshing, and no refresh off screen;
    - rows opening their screen with the sub-tab, the day or the member;
    - the empty, loading (bars 180, 130 and 160px wide) and no-raid states; guarded refreshes; a Now tab that failed to build not retried; no
      timers while hidden.
  - **The calendar filter, run for real:** the real Guild tab and calendar open on a day in another month, with
    that month shown, the day selected and both drawn; opening the calendar without a day keeps the selection.
  - **Sub-tabs:** the real Guild tab's bar is 28px on `panel`, its four sub-tabs carry the 1px rule, shown under
    the open one. Leadership, Audit, Raid Tools, Alliance, Recruitment and Raids are checked in their source: the
    28px bar, `StyleSubTabBar` on it, and `CreateTab(…, true)`.
  - **Leftovers and wiring:** no source reference to the removed API; `SelectSub` exposed by every panel with
    sub-tabs; the Raids bar at 28px; the home cards through `OpenWindow`.
  - **SelfTests:** the in-game `features.*`, `window.geometry_roundtrip` and `ui.titlebar_button_outranks_bar`, plus
    the registry refusing a tab with nothing to build.
- `tools/layout-ladder.lua` (67 checks) and `tools/layout-tabs.lua` (17 checks), both against the real `UI/Layout.lua`.
  - The ladder: the table, thresholds, hysteresis both ways, jumps, wobble.
  - Tab fit: exact fit, a pixel over, the room "»n" takes, an active tab that shows, overflows or cannot fit.
- `tools/forever-components.lua` gains 4 checks (142): the sub-tab's 1px rule, the tab's 2px one, an active
  sub-tab, a sub-tab bar on `panel`.
- `tools/probe.lua`: the window registers each event in its own literal call, so the drift check still sees them.
- Still passing: `forever-skin` (348), `client-detection`, `public-note`, `startup-isolation`, `roster-import`,
  `attendance-parity`. `luacheck` is clean apart from the known `Inbox.lua:5` warning.
- **Mutation check:** 226 hand-written mutants; the two harnesses kill all 226.
  - **Round 4:** a window that cannot move or resize, a grip or title bar that does nothing, a tab click that is not
    remembered or does nothing, a dead close button, Now not first or not core, the chrome's lines, "»n" at the left,
    footer actions and the invite doing nothing, a hidden Now refreshing, a calendar button that is not primary.
  - **Round 5:** every panel's sub-tab bar at 40px, off `panel`, or with 2px rules; the window on MEDIUM; the
    start-up record unnamed; a closed window refreshing its title; the weekday after an hour.
  - **Round 6:** "»n", the selector and the footer actions not ghost; the home cards over the column; the cards
    over each other; activity short of the bottom; the home cards from 781px.
  - **Window:**
    - the clamp, restore, scale, and every save;
    - resize bounds, grip size, clipping;
    - the remembered tab, forced switches, the tab gate, fall-back, toggles, build refusal, events, the ticker;
    - "»n", overflow, the active tab, the selector;
    - the band measured on the content area (layout and settle), band keys, title height, padding, bar visibility,
      the close position, the watch retry, fold and restore (padding, saved fold, immediate layout, a re-drag
      keeping the size), the title on unfold, the 620px padding edge;
    - what is seen: the wordmark's colour and text, the title bar's surface, the rule's line, the sync colour,
      the footer inset, the tab label size;
    - OpenWindow's refusals, unfold, sub-tab and filter;
    - meta and its loading dash, a title that walks the officer work or is unguarded, Escape, the binding, the
      footer.
  - **Now:**
    - sync, loading, the calendar guard, the next raid, clock, short form;
    - needs: order, gates, the week, the day filter, the trial threshold, ready trials counted twice;
    - activity: window, 48h, fallback, order, limit, member keys and ambiguity, loot member, action texts, both
      milestone kinds, the raid's time;
    - the bar: order, dash, loading dashes, gold;
    - the column: home width and build once, a resize that refetches, the 12-row cap, loading and empty states,
      mark and time sizes, the countdown's colour, row positions, text anchors, bar widths, the weekday stamp,
      hover on empty rows, the promotions row's wording, row opening and filters, the tick and the roster event, the calendar button (shown, hidden, its day),
      guarded refresh, timers.
  - **Elsewhere:**
    - the sub-tab rule and bar, every exposed `SelectSub`, the Raids bar;
    - the Guild tab's filter, its check and its argument; the calendar's day, month and redraw;
    - `/gos` bare, `/gos banlist` and `/gos calendar`, the open verb;
    - the minimap click, the guild key, the native button, `RefreshRosterUI`;
    - Now's builder and label, the registry invariant, the front door;
    - the binding and its category, the minimap menu, Core Sign-up's anchor, the home cards.
- **Manual on Anniversary:** each ladder band, the fold, a deep link, with screenshots.

## 4. Plan and tasks (one PR, staged commits once commits are allowed)
- [x] 1. Ladder and tab fit in `Layout.lua`, with tests
- [x] 2. The shell: size, bounds, grip, persistence, scale, title bar, footer
- [x] 3. One way in: `OpenWindow` / `ToggleMain`, entry points and key binding, uniform `SelectSub`; hub and windows removed
- [x] 4. Tab overflow "»n" wired to `FitTabs`; sub-tab style
- [x] 5. Ladder applied: selector and Now under 520, the bar under 420
- [x] 6. Now from the hub's live blocks
- [x] 7. `tools/window-shell.lua`; docs (ADR-0016, catalog, UI architecture); in-game `window.*` self-test on the one window
- [x] 8. Review round 1:
  - fold after `/reload`, the trial threshold, the binding category, the watch retry;
  - a cheaper resize, guarded refreshes;
  - the band on the content area, row filters, loading dashes, the Raids bar;
  - entry points tested for real
- [x] 9. Review round 2:
  - a trial counted twice, in its row and in the suggestions;
  - member lookups only for the rows kept;
  - checks for the calendar filter through the real Guild tab, the size a re-dragged bar opens back to, the
    column's cap, the title on unfold and the 620px edge
- [x] 10. Review round 3: checks for what the criteria and spec say is seen; the promotions row named for what it
  counts
- [x] 11. Review round 4: checks for moving and resizing, tab clicks, close, Now first and core, the chrome's
  lines, "»n"'s edge, footer actions and the invite, no refresh off screen, the primary calendar button
- [x] 12. Review round 5: the sub-tab criterion on the real Guild tab and every other bar, the strata, the
  start-up record's name, a closed window's title, the weekday boundary
- [x] 13. Review round 6: the ghost controls, Now's card anchors and the 780px line
- [ ] Manual check on Anniversary at each band, with screenshots

## 5. Decisions and open questions
- **Minimise:** folds to the 28px bar and keeps the size; "+" restores it.
- **Sync time or raid countdown in the title bar:** the issue's sync time; the countdown is in Now and the bar.
- **Where the ladder measures:** the content area, the panel that hosts every tab's tables. The chrome and the
  tables read the same width.
- **Row filters:** the sub-tab, the calendar's day or the member, where the owning screen has one; the rest open the
  screen.
- **Missing data:** §2.5's follow-up list becomes separate issues rather than widening #14.
- **Roster beside the column at 760px (the handoff's day-to-day artboard):** left to #15, which owns the home and
  roster screens. Until then, the column fills the tab under 780px.
