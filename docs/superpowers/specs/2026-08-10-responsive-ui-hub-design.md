# Responsive panels + command-centre hub

The modular UI shipped on `feat/modular-ui` works: the addon now opens as a small card and every
feature is its own floating window. Two things came back from live use.

**Panels leak outside their window.** Roster, Recipes, Recruitment and Leadership all draw content
past the window edges, onto the rest of the screen.

**Title-bar buttons are dead.** No close button works, in any window or in the hub. The hub's gear
and expand buttons are dead for the same reason.

**The hub is too small to be useful.** It is a menu with a two-line pulse band. It shows almost
nothing about the guild.

Design round held 2026-08-10 (hub shape, right-column blocks, fix strategy and narrow-width column
behaviour all signed off by the user).

## 1. Root causes

Confirmed in the code, not guessed.

### 1.1 Dead title-bar buttons

`UI/RosterFrame.lua:1108` has the working pattern:

```lua
local closeBtn = UI:CreateCloseButton(titleBar)
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -10)
closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
```

The close button is a child *of the title bar* and its frame level is explicitly raised above it.
`UI/Window.lua:110` and `UI/Hub.lua:79-93` do neither: the button is a sibling of the bar at the
same frame level, and the bar is `EnableMouse(true)` with `RegisterForDrag` spanning the full
width. The bar swallows the click. In the hub the bar is a `Button` with an `OnClick` that
collapses the card, so `x`, gear and expand are all inert.

### 1.2 Leaking content

Three causes stack.

1. **Fixed layout maths sized for the old main frame.** `UI/RosterFrame.lua:50` sets
   `FRAME_WIDTH = 1080 + RAIL_WIDTH` = 1236, and `cardX(i)` at line 288 lays the six KPI cards out
   across that width. In a 1000px window the sixth card starts at x = 1030. That is exactly what
   the screenshot shows.
2. **Fixed row counts.** `VISIBLE_ROWS = 18` at 32px (roster) and `VISIBLE_ROWS = 20` at 24px
   (recipes) need more height than the window has. Leadership lays 8 sub-tabs at `x = x + 120`,
   960px inside a 760px window.
3. **No clipping.** `win.content` (`UI/Window.lua:137`) does not clip its children, so the overflow
   renders over the rest of the screen instead of being cut off.

## 2. Goals and non-goals

**Goals**

- Every windowed panel lays itself out from the container's real size, at any size between its
  minimum and full screen.
- Dragging the resize grip reflows the panel: columns appear and disappear, row counts change,
  sub-tab bars wrap.
- Nothing can draw outside a window, including panels not yet converted.
- Every title-bar button works, in every window and in the hub, and cannot silently break again.
- The hub becomes a command centre: what is happening in the guild and what needs the user's
  attention, each line clicking straight through to the right place.

**Non-goals**

- No change to what any panel *does*. This is layout and one input bug, not features.
- No new data sources. The hub reads what modules already expose.
- Expanded mode is not removed or reworked. It hosts the same panels and benefits for free.
- No per-panel saved column widths or user-reorderable columns.

## 3. The layout layer (new `UI/Layout.lua`)

One module, four primitives, no frames of its own. Pure functions where possible so
`/gos selftest` can exercise them without a live UI.

### 3.1 `UI:MakeResponsive(container, layoutFn)`

Hooks `container:SetScript("OnSizeChanged", ...)`, coalesces the burst of events a drag produces
into one recompute per frame (`C_Timer.After(0, ...)` behind a `__layoutPending` flag), and fires
once on the first `OnShow` so the initial layout is correct before the user touches anything.
`layoutFn(container, width, height)`.

A panel opts in with one line. A panel that has not opted in still gets clipping (3.5) and so
degrades to "cut off" rather than "painted over the screen".

### 3.2 `UI:ResolveColumns(spec, width)`

```lua
spec = {
  { key = "name",  min = 120, weight = 3, priority = 100 },
  { key = "lvl",   min = 34,  weight = 0, priority = 95  },
  ...
}
```

Algorithm:

1. Start with every column shown.
2. While the sum of `min` (plus gaps) exceeds `width`, drop the shown column with the lowest
   `priority`, but never drop a column marked `required`.
3. Distribute the remaining space across the survivors by `weight`. A `weight` of 0 keeps the
   column at exactly `min`.

Floor case: when even the `required` columns do not fit their minimums, nothing more is dropped.
They shrink below `min` proportionally and their text truncates. A degraded table beats an empty
one, and it keeps the function total for any input.

Returns `{ key, x, w, shown }` per column. This is the single definition of "columns disappear by
priority", used by the roster table, the roster KPI band, the recipes table and the Leadership
lists.

### 3.3 `UI:ResolveRows(height, rowH, reserved)`

`floor((height - reserved) / rowH)`, clamped at 0. `reserved` is the non-row chrome inside the same
area: column header, footer, paging strip. Replaces every `VISIBLE_ROWS` constant. Callers acquire
and show exactly that many pooled rows and hide the rest.

### 3.4 `UI:FlowBar(bar, buttons, gap)`

Lays buttons left to right, wrapping to a new row when the next one does not fit. Returns the total
height so the content below can anchor to it. Button width comes from the label, not a fixed
constant.

### 3.5 Clipping as a safety net

In `UI:CreateWindow`, guarded because the method may not exist on every client build:

```lua
if content.SetClipsChildren then content:SetClipsChildren(true) end
```

Same for the expanded-mode tab panels. This does not replace responsive layout. It guarantees that
a layout bug is a visual truncation inside one window, never a paint over the whole screen.

### 3.6 Registry minimums

`UI/Features.lua` gains real `minW` / `minH` per feature, derived from the sum of each panel's
mandatory columns rather than the generic 380x260 fallback in `UI/Window.lua:117`. Roster:
`minW = 520`, `minH = 380` (see 5.3 for where 520 comes from).

## 4. The hub

430px wide, height driven by content. Left rail 150px, right column 280px.

```
+--------------------------------------------------------------+
| GUILD OS                                     [ ]   *    x    |
+--------------------------------------------------------------+
| Abaixo da Curva . 58 membros . 3 online                 v    |
+------------------+-------------------------------------------+
| > Roster      58 |  ONLINE AGORA                         3   |
| > Raids          |   . Chehul            70  Hunter          |
| > Loot         2 |   . Hodenhador        69  Druid           |
| > Recipes        |   . Sthealf           28  Rogue           |
| > Guild          |                                           |
| > Alliance       |  PROXIMO EVENTO                           |
| > Recruit        |   Karazhan                                |
| > Trials       1 |   sab 21:00 . em 2d 4h                    |
| > Leadership   3 |                                           |
| > Settings       |  PRECISA DE VOCE                      4   |
|                  |   > 3 inativos ha mais de 30d             |
|                  |   > 1 trial vence hoje                    |
|                  |   > 2 candidatos no inbox                 |
|                  |                                           |
|                  |  VOCE                                     |
|                  |   120 DKP . presenca 86% . 2 na wishlist  |
+------------------+-------------------------------------------+
| ... mais                                        Fechar tudo  |
+--------------------------------------------------------------+
```

### 4.1 Left rail

The existing feature rows, unchanged in behaviour: pooled, built from `UI:VisibleFeatures("hub")`,
dot when the window is open, badge count on the right, click toggles the window.

### 4.2 Right column blocks

Rendered in order; each one that has nothing to say either shows its empty state or is skipped
entirely, and the blocks below move up.

| Block | Source | Empty state | Click target |
|---|---|---|---|
| ONLINE AGORA | `GetGuildRosterInfo` loop, same as `Hub:Refresh` does today | "So voce online" | The member's `MemberDetail` |
| PROXIMO EVENTO | `BRutus.Calendar:NextEvent()` | "Nenhum evento agendado", plus a "criar" link for officers | Guild window, calendar sub-tab |
| PRECISA DE VOCE | inactivity, trials, suggestions, recruitment inbox | "Tudo em dia" in green | Per line: Leadership/inactivity, Trials, Leadership/suggest, Recruitment |
| VOCE | points/DKP, attendance, wishlist | Line omitted if the module is off | Respective window |

`ONLINE AGORA` shows at most 5 names; beyond that a "+N mais" line opens the Roster.
`PRECISA DE VOCE` shows at most 4 lines and is **hidden entirely for non-officers** (gated on
`BRutus:IsOfficer()`), with the blocks below moving up. `VOCE` is never hidden: it is what makes
the hub worth opening for a rank-and-file member.

### 4.3 Collapsed state

Collapsing now summarises instead of going blank:

```
+--------------------------------------------------------------+
| GUILD OS   3 online . Kara em 2d . 4 !       [ ]   *    x  > |
+--------------------------------------------------------------+
```

The collapse control is the `v` / `>` chevron at the right of the header line, not the title bar.
The bar goes back to being drag only, which is what frees the title-bar buttons (5.1).

### 4.4 Refresh cadence

Today the hub only refreshes when a window opens or closes. It gains `GUILD_ROSTER_UPDATE` plus a
10s ticker, both **only while shown**: the ticker starts on `OnShow` and stops on `OnHide`, so a
hidden hub costs nothing.

## 5. Panel conversions

### 5.1 Title-bar buttons

New helper, so the pattern exists in exactly one place:

```lua
function UI:TitleBarButton(bar, kind, ...)  -- kind: "close" | "text"
    local btn = (kind == "close") and self:CreateCloseButton(bar) or self:CreateButton(bar, ...)
    btn:SetFrameLevel(bar:GetFrameLevel() + 5)
    return btn
end
```

Three call sites adopt it:

- `UI/Window.lua:110` for every floating window's `x`.
- `UI/Hub.lua:79-93` for `x`, gear and expand. The bar loses its collapse `OnClick`; the chevron
  takes over.
- `UI/RosterFrame.lua:1106` replaces its manual `+5` bump so there is one definition.

### 5.2 Per-panel work

| Panel | File | Change |
|---|---|---|
| Roster | `UI/RosterFrame.lua` | KPI band through `ResolveColumns` (MEMBROS, ONLINE, iLVL never drop; then ATENDIMENTO, COM GUILD OS, PLAYERS). Table columns through `ResolveColumns` per 5.3. `VISIBLE_ROWS` through `ResolveRows`. Rail stays 156px fixed. Search box and "Show Offline" anchor to TOPRIGHT. |
| Recipes | `UI/RecipesPanel.lua` | `VISIBLE_ROWS = 20` through `ResolveRows`. RECIPE and CRAFTERS flex, PROFESSION fixed at 120 and drops below 520px. The 10 profession icons through `FlowBar`. |
| Leadership | `UI/ManagementPanel.lua` | 8 sub-tabs through `FlowBar`; `makeSubPanel`'s hardcoded `-42` becomes the returned height. Tab width from the label. The six list sub-panels (ranks, inactivity, suggestions, log, ban, engagement) share one list helper using `ResolveRows` + `ResolveColumns` instead of six copies. |
| Recruitment | `UI/RosterFrame.lua:2560+` | `SetWidth(700)` / `SetSize(680,40)` / `SetSize(400,22)` become TOPLEFT+TOPRIGHT anchors with margins. The section stack does not shrink, so it gains a real vertical scroll frame. **Gotcha: `UI:CreateScrollFrame` does not anchor the scroll frame; the caller must `SetAllPoints` or the content clips to 0x0 and vanishes with no error.** |
| Alliance | `UI/AlliancePanel.lua` | Sub-tabs at `x + 124` through `FlowBar`. The four `SetWidth(460)` hint texts anchor to the container. |
| Raids / Loot / Trials | `UI/FeaturePanels.lua` | The `SetSize(800, 1)` scroll contents follow their scroll frame's width. |
| Cores | `UI/CorePanel.lua` | `LIST_W = 220` left column stays; the right pane anchors to the container. |
| Home | `UI/Dashboard.lua` | Same sweep, tab-only surface. |

### 5.3 Roster column priority

Signed off by the user. MEMBRO, LVL and CLASSE never drop. The spec that produces it:

| Column | min | weight | priority | required |
|---|---|---|---|---|
| MEMBRO | 150 | 3 | 100 | yes |
| LVL | 34 | 0 | 95 | yes |
| CLASSE | 74 | 1 | 90 | yes |
| iLVL | 46 | 0 | 80 | no |
| RACA | 70 | 1 | 60 | no |
| VISTO | 78 | 1 | 50 | no |
| PROFISSOES | 160 | 2 | 40 | no |
| ZONA | 120 | 2 | 30 | no |

Gap between columns is 10. Drop order follows `priority` ascending: ZONA, PROFISSOES, VISTO, RACA,
iLVL.

MEMBRO's 150 absorbs the existing unlabelled 20px `status` column (`UI/RosterFrame.lua:29`), which
holds the online dot. The dot is visually part of the name cell (dot, class icon, name), so it
rides along instead of being a droppable column of its own.

**Table area** is the window width minus the 156px rail and 24px of margins, so
`table = window - 180`. The resulting breakpoints, which `layout.columns_drop_by_priority` asserts
against:

| Table width | Window width | Columns shown |
|---|---|---|
| >= 802 | >= 982 | all 8 |
| 672 .. 801 | 852 .. 981 | drops ZONA |
| 502 .. 671 | 682 .. 851 | also drops PROFISSOES |
| 414 .. 501 | 594 .. 681 | also drops VISTO |
| 334 .. 413 | 514 .. 593 | also drops RACA: MEMBRO, LVL, CLASSE, iLVL |
| < 334 | < 514 | floor: MEMBRO, LVL, CLASSE |

Roster `minW = 520` sits inside the four-column band, so that is the narrowest state the grip can
reach and the three-column floor is unreachable by dragging. It still has to behave, because
expanded mode and a high UI scale can produce it.

## 6. Testing

Added to the existing `/gos selftest` harness, all runnable without a live UI:

- `layout.columns_drop_by_priority` : at 1240 / 900 / 700 / 520 the shown set matches 5.3 exactly.
- `layout.columns_fit` : the sum of resolved widths never exceeds the available width, and no shown
  column is below its `min`.
- `layout.columns_never_empty` : at absurdly small widths the mandatory columns still survive.
- `layout.rows_fit` : `ResolveRows` never returns a count whose total height exceeds the available
  height, and never returns a negative count.
- `layout.flowbar_wraps` : 8 tabs in 760px return 2 rows and the height of 2 rows.
- `ui.titlebar_level` : for every created window, the close button's frame level is strictly greater
  than the title bar's. This is the test that keeps the dead-button bug from returning.

Manual verification, on top of the harness: open each window, drag the grip to the minimum and to
full screen, confirm nothing draws outside the frame and every title-bar button responds. Plus
`luacheck` clean.

## 7. Risks

- **Wide blast radius.** The conversion touches `RosterFrame.lua` (129k), `FeaturePanels.lua`
  (183k), `AlliancePanel.lua` (65k) and `ManagementPanel.lua` (47k). Mitigation: the layout layer
  and the clipping net land first and are independently verifiable, so every later panel commit is
  small and reversible on its own.
- **`SetClipsChildren` availability.** Guarded by an existence check; if it is missing the panels
  are still responsive, they just lose the safety net.
- **Reflow cost during a drag.** Coalescing to one recompute per frame bounds it. Row pools are
  reused, never re-created, which is already how the roster and the hub work.
