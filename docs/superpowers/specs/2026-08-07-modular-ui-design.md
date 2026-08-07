# Modular UI design (minimal hub + floating feature windows)

Repeated user feedback says the addon is too big and eats the screen. Today Guild OS opens as a
single 1236x808 window with 13 top-level tabs, several of which are hubs with their own sub-tab
bars. It is the whole addon or nothing.

This design breaks that into a small always-optional hub card plus one floating, draggable window
per feature — the RestedXP-style experience — while keeping the current full window alive as an
opt-in "expanded mode". Nothing the addon does today is removed.

Design round held 2026-08-07 (hub shape, fate of the big window, window granularity, window
behaviour and the modularity/toggle rule all signed off by the user).

## 1. Goals and non-goals

**Goals**

- Opening the addon costs a ~230px card, not a 1236x808 window.
- Every feature opens as its own small, draggable, position-remembering window.
- Several windows can be open at once; nothing opens that the user did not ask for.
- Turning a feature off in Settings makes it disappear from every entry point.
- The current full window stays available for people who like it.
- No panel builder is rewritten. The diff is in the container, not in the 18 panel files.

**Non-goals (explicitly out of scope)**

- Magnetic snapping / docking between windows.
- Saved layout profiles, per-spec or per-character layout sets.
- Drag-a-window-onto-another to merge into tabs.
- Open/close animations beyond the existing fade, per-window themes.

All four were considered and dropped in the design round: none of them addresses "it takes up too
much screen", and each is a growth vector for exactly the bloat this design is undoing.

## 2. Decisions from the design round

| Question | Decision |
| --- | --- |
| What is the minimal hub | A compact card (~230px wide), header + live pulse + clickable feature rows |
| Fate of the 1236x808 window | Survives as opt-in expanded mode, fed by the same registry |
| Window granularity | One window per current top-level tab (13); existing sub-tab bars stay inside |
| Window behaviour | Multiple open at once, each remembers position and size, ESC closes the top one |
| Modularity | Disabling a feature in Settings removes it from hub, tabs, minimap menu and slash |

## 3. Current state

Facts that shape the design (measured, not assumed):

- `UI/RosterFrame.lua:50-51` — the frame is `1080 + 156` wide by `36 + 32*18 + 150 + 82` tall.
- `UI/RosterFrame.lua:486-505` — 13 `CreateTab` calls, hardcoded.
- `UI/RosterFrame.lua:510-1127` — every tab panel is built eagerly on frame creation.
- Panel builders share a uniform shape: `BRutus:CreateXPanel(container, mainFrame)`. The container
  does not know whether it is a tab panel or anything else. **This is the seam the design uses.**
- 11 standalone floating windows already exist (Search, Digest, CraftFinder, PugInspector, GuildMap
  list, Bulletin, GuildAnalytics, RecruitBeacon, AllyCard, EventEditor, Onboarding). Each hand-rolls
  the same `SetMovable` / `RegisterForDrag` / `UISpecialFrames` boilerplate, and **none of them
  persists its position**.
- Feature on/off state already exists as `db.settings.modules[key]`, but the list is hand-written in
  `UI/FeaturePanels.lua:1830-1841` and read by a *local* `modEnabled()` inside `InitModules`
  (`Core/Core.lua:236-240`). It is not public API, and it is a second list describing the same
  features as the tab list.
- `GuildOSDB` is partitioned per guild (`Core/Core.lua:188`), not per character.

## 4. Architecture: one container, one registry

Four new files: `UI/FeatureRegistry.lua` (the registry API), `UI/Window.lua` (the generic container),
`UI/Features.lua` (the entries), `UI/Hub.lua` (the hub card).

### 4.1 `UI/Window.lua` — the generic container

```lua
UI:CreateWindow(id, opts)   -- obsidian backdrop + title bar + close + drag + resize grip
                            -- + Helpers:StylePopup() + UISpecialFrames entry
                            -- + geometry save/restore
                            -- + lazy build: opts.build(container, win) runs on first Show
UI:OpenWindow(id, subKey)   -- create on demand, show, raise, select sub-tab
UI:ToggleWindow(id)
UI:CloseAllWindows()
```

`opts`: `title`, `w`, `h`, `resizable`, `minW`, `minH`, `build`.

### 4.2 `UI/FeatureRegistry.lua` — the registry

One entry is the complete identity of a feature:

```lua
UI:RegisterWindow{
    id          = "raids",
    label       = L["Raids"],
    icon        = "Interface\\Icons\\INV_Sword_04",
    order       = 20,
    w = 780, h = 540, resizable = true,
    subs        = { "sessions", "raiders", "cores", "audit", "raidtools" },
    officerOnly = false,
    core        = false,           -- true = cannot be disabled (roster, settings)
    hub         = true,            -- false = no hub row and no floating window
    tab         = true,            -- false = no tab in expanded mode
                                   -- both false = background module, Settings toggle only
    module      = "raidTracker",   -- optional: background module this feature gates
    badge       = function() return ... end,  -- optional: pending count for the hub row
    build       = function(container, win) BRutus:CreateRaidHubPanel(container, win) end,
}
```

From this single table come: the hub rows, the expanded-mode tabs, the minimap context menu, the
slash commands and the Settings toggle list. Adding a feature means adding one entry.

### 4.3 The trick that keeps the diff small

Panel builders receive `mainFrame` and call `mainFrame:SetActiveTab(key)` and
`mainFrame.tabPanels[key].SelectSub(sub)` for cross-navigation (e.g. `UI/Dashboard.lua:53-60`).

`Window` implements **the same interface**:

```lua
function win:SetActiveTab(key)          -- window mode: navigate = open that window
    UI:OpenWindow(key)
end
win.tabPanels = setmetatable({}, ...)   -- returns a shim exposing SelectSub for the target window
```

So a panel does not know or care which container it lives in. **Zero panel files change.**

Two alternatives were considered and rejected:

- *Reparent the same panel between the tab and a window at runtime* — fragile; `SetAllPoints` and
  anchor chains break on reparent, and two parents means two frame levels to keep in sync.
- *Rewrite each panel as a self-contained window* — 18 files touched for no user-visible gain.

### 4.4 Free win: lazy build

Because `build` runs on first `Show`, opening the addon now constructs one window instead of 13
panels and all their sub-panels.

## 5. The hub (`UI/Hub.lua`)

~230px wide, height driven by the enabled row count. Collapses to its 24px title bar.

```
+----------------------------+
| (icon) GUILD OS   [⛶][⚙][X]|   drag by header; click header collapses
+----------------------------+
| * 14 online · 62 members   |   pulse band (toggleable in Settings)
| ~ Kara in 2d 4h · you: yes |
+----------------------------+
| * Roster                   |   * = window currently open; click toggles
|   Raids                    |
| * Loot                     |
|   Recipes                  |
|   Guild                  2 |   badge = real pending count only
|   Alliance               3 |
|   Recruitment              |
|   Leadership               |   officerOnly rows hidden for non-officers
+----------------------------+
| ... more          X all    |
+----------------------------+
```

- Rows: 22px, icon + label + optional badge. Click toggles that window.
- `... more` swaps the card to a second page (same card, no new window) listing the loose tools
  (Search, PugInspector, CraftFinder, Guild Map, Consumable Check) and sub-tab deep links
  (`Raids > Audit` opens the Raids window on its Audit sub-tab).
- `⛶` opens expanded mode. `⚙` opens Settings. `X all` closes every open feature window.
- Badges show only real pending counts (recruitment applications, unread alliance messages). No
  decorative badges.
- The hub absorbs the role of the current Home dashboard. `UI/Dashboard.lua` stays as the Home tab
  of expanded mode — no deletion, no duplication of effort.
- There is no "everything disabled" empty state, because there cannot be one: `roster` and
  `settings` are `core = true`, so the hub always has at least two rows. An unreachable fallback row
  would be dead code pretending to be a safety net.
- **One predicate answers "is Guild OS showing?"** The native guild-frame hook
  (`Core/Core.lua:462-499`) mirrors Blizzard's open/close onto the addon and used to ask
  `RosterFrame:IsShown()`. With the hub as the front door that question has two possible answers, so
  it becomes `BRutus:IsFrontDoorShown()` — hub visible, or expanded window visible. Without it,
  pressing the guild button while the hub is open toggles the hub closed, and closing the native
  frame stops closing ours.

## 6. Window inventory

| id | default size | resizable |
| --- | --- | --- |
| roster | 1000x620 | yes |
| alliance | 900x600 | yes |
| raids (5 sub-tabs) | 780x540 | yes |
| management | 760x540 | yes |
| guild | 720x520 | yes |
| recruitment | 720x500 | yes |
| recipes | 700x500 | yes |
| loot | 680x470 | yes |
| wishlist | 680x470 | yes |
| dkp | 620x440 | yes |
| trials | 620x420 | yes |
| settings | 560x520 | no |

Twelve windows, not thirteen: the `home` tab has no window of its own — the hub is what replaced it,
and `home` stays registered as expanded-mode-only (`hub = false`).

Plus a global `db.settings.uiScale` (0.8–1.2), applied with `SetScale` to the hub and every window.
Part of "it is too big" is literally screen resolution, and this costs three lines.

## 7. Modularity and toggles

`BRutus:IsFeatureEnabled(id)` becomes public API — a promotion of the existing local `modEnabled`
with identical semantics (`db.settings.modules[id] ~= false`, default on). Registry ids and module
keys become the same key space.

Consumers and the effect of switching a feature off:

| Consumer | Effect |
| --- | --- |
| Hub row list | Row disappears |
| Hub `... more` page | Deep link disappears |
| Expanded-mode tab bar | Tab disappears (`UpdateTabVisibility` already supports this via `condition`) |
| Minimap context menu | Item disappears |
| `/gos <id>` | Replies "feature disabled" |
| A window of that feature open at the time | Closes itself |
| Hub pulse band | A line disappears if its source feature was disabled |

**Live, no reload** — because windows are lazy-built, disabling is hide + close and re-enabling just
lets the window be born on the next click. The current `Reload UI to apply` message stays valid only
for background modules that register events at `Initialize` (comms, trackers, chat tweaks); the
registry's `module` field says which entries those are, so the warning is printed only where it is
true.

The Settings screen **generates** its toggle list from the registry, deleting the hardcoded `modules`
table at `UI/FeaturePanels.lua:1830-1841`.

Guards:

- **`officerOnly` is enforced at every opener, not only at the row.** Hiding a hub row or not drawing
  a tab button is presentation, not access control. There are three openers and all three gate:
  `UI:OpenWindow(id, sub)` (reachable from a slash command), sub-tab selection (reachable from a
  deep link), and `frame:SetActiveTab(key)` in expanded mode — which the Home dashboard's cards call
  directly via `goTab`, with no button involved. The gate is defined once, next to
  `UpdateTabVisibility`, and both consumers call it; a second copy is how the definitions drift
  apart. Note the failure mode is not obvious: while gated-out tab panels did not exist, an ungated
  `SetActiveTab` merely did nothing, so creating the panels unconditionally is what turns a silent
  no-op into a leak. Otherwise `/gos open management` renders the Leadership panel for
  any member, and a sub-tab deep link walks past a button that was never drawn. The expanded-mode
  path already defends this (`Core/Core.lua:606-613`); the window path must match it. The exposure is
  information disclosure — mutating actions re-check `IsOfficer()` independently — but the rule holds
  either way: the check belongs where the panel is opened.
- `core = true` on `roster` and `settings` — they have no toggle, so a user cannot lock themselves
  out of the UI that would let them back in.
- Disabling never destroys data. It hides UI and (for `module` entries, after reload) stops
  background event handling.

## 8. Persistence

```lua
db.settings.windows[id] = { point = "CENTER", x = 0, y = 0, w = 780, h = 540 }
db.settings.hub         = { point, x, y, collapsed = false, shown = true, pulse = true }
db.settings.uiScale     = 1.0
```

Saved on `OnDragStop` / `OnSizeChanged` (debounced), restored on first `Show`.

Which windows were open is deliberately **not** saved: logging in must not throw five windows back
onto the screen. Only the hub restores its own state.

`ponytail:` per-guild layout (the DB is partitioned per guild at `Core/Core.lua:188`), so alts in the
same guild share one layout. Upgrade path if anyone complains: add `SavedVariablesPerCharacter` and
read layout from there — not a refactor.

## 9. Expanded mode

Unchanged behaviour, but the tab bar is generated from the registry instead of the 13 hardcoded
`CreateTab` calls. Same builders, same sub-tabs, same `SetActiveTab`. `⛶` on the hub opens it; `⛶`
on its title bar returns to the hub. Tab visibility keeps honouring `officerOnly`, `condition` and
now `IsFeatureEnabled`.

**Tab frames are created ungated — by *no* filter, not merely by "not the toggle".** `AllFeatures`
still applies `officerOnly` and `condition`, which is right for the Settings list but wrong here:
gates evaluated once at construction cannot be re-evaluated later, and `UpdateTabVisibility` exists
precisely to re-evaluate them on every event. Bake them in and a `dkp` tab can never appear when the
guild switches loot system mid-session (`SetLootSystem` advertises itself as reload-free), an
`alliance` tab can never appear when a pact forms, and a promoted officer sees no `loot`/`trials`/
`management` until `/reload`. Expanded mode iterates every feature with `tab = true` and nothing
else; `UpdateTabVisibility` owns every gate.

**Lazy build changes when a panel's methods exist.** `CreateRosterPanel` installs `RefreshRoster` on
its host, so with lazy build that method does not exist until the Roster tab is first activated —
and the window opens on Home. Any caller that guards only on `IsShown()` will error. All roster
refreshes go through `BRutus:RefreshRosterUI()`, which nil-guards the method and covers both
containers; no caller reaches `RefreshRoster` directly.

## 10. Rollout

Each phase ships on its own.

1. **Foundation** — `UI/Window.lua`, `UI/Windows.lua`, public `IsFeatureEnabled`. Nothing visible
   changes yet.
   One prerequisite surfaced while planning: **the roster panel has no builder.** Every other tab
   has one (`CreateRecipesPanel`, `CreateGuildHub`, `CreateDKPPanel`, ...), but the roster is still
   written inline inside `CreateRosterFrame` (`UI/RosterFrame.lua:520-1012`) and assigns 24 fields
   and methods to the frame. It has to be extracted into `BRutus:CreateRosterPanel(parent, host)`
   before a window can host it — a behaviour-free refactor, verified against the current UI, and the
   riskiest edit in the whole rollout.
2. **Hub** — `UI/Hub.lua`; minimap button and `/gos` open the hub; expanded mode reachable via `⛶`.
3. **Registry-driven expanded mode** — `RosterFrame` builds its tabs from the registry, panels go
   lazy; delete the 13 `CreateTab` calls and the hardcoded Settings `modules` list.
4. **Migrate the 11 ad-hoc windows** — Search, Digest, CraftFinder, PugInspector, GuildMap, Bulletin,
   GuildAnalytics, RecruitBeacon, AllyCard, EventEditor, Onboarding move onto `UI:CreateWindow`.
   Deletes ~10 copies of the same drag boilerplate; all 11 gain saved positions for free. Pure
   deletion — can wait.

## 11. Verification

`Modules/SelfTest.lua` is the existing in-client harness. Register one case covering the registry
invariants:

- every entry has `id`, `label`, and — when `hub` is true — `build` and a positive `w`/`h`;
- ids are unique;
- `subs`, when present, is a list of non-empty strings;
- `core = true` implies `IsFeatureEnabled(id)` is always true, including with
  `db.settings.modules[id] = false`;
- disabling and re-enabling a feature round-trips through `SetFeatureEnabled` / `IsFeatureEnabled`.

A wrong `subs` key cannot be caught statically — sub-tabs are created by the builder at build time —
so a deep link to a key the builder does not know silently does nothing. That is the accepted
failure mode; the alternative is builders declaring their sub-tabs twice.

Failures surface on `/gos selftest` instead of as a black window in raid.

Geometry save/restore is checked by the same case shape: write a geometry table, restore it into a
detached frame, assert the point round-trips.

## 12. Deferred (known ceilings)

- Per-guild rather than per-character layout (see section 8).
- No window "maximize"; resize grip plus saved size covers it.
- The `... more` page is a flat list; if it grows past ~12 entries it wants grouping.
