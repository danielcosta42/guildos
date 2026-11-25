# Plan: the Salão, phase 1 (#445)

## Decisions

1. **One look, two ways of drawing it.**
   - `Core/Style.lua` keeps its two painters: the client's art (`forever`) and the flat one
     (`guildos`). They become ways of drawing, no longer styles to choose.
   - `Style:Resolve()` ignores `GuildOSDB.style`. It always re-points the palette to the stone and
     bronze one and always takes the game's font. It paints with the art where `Style:Has("forever")`
     and flat elsewhere.
   - `Style:Available()` returns only the mode in use, so Settings' picker (`BuildPicker`, which draws
     nothing under two styles) disappears with no code of its own.
   - `Style:Apply` and `/gos style <id>` answer that there is one look.
   - Why this way:
     - It is the smallest change that gives every client the same palette and font. P6 (simplicity):
       no new painter.
     - It keeps every `Style:Skin*` call site as it is.
2. **The game's font everywhere.**
   - `GuildOS:ApplyFont` already falls back to `STANDARD_TEXT_FONT` when `Style.gameFont` is set (#57).
   - Setting it always is the whole change. Settings' "game font" toggle loses its meaning and leaves.
   - The Plex files stay in `Media/Fonts` for this phase. Nothing loads them, and removing them is a
     packaging change for a later phase.
3. **Rooms are a layer over the features, not a new registry.**
   - `UI/Rooms.lua` holds the table of rooms and entries, plus three pure functions:
     - `UI:RoomOf(id, sub)`: the room and entry that hold a feature (and sub-tab);
     - `UI:RoomEntries(room)`: the entries that may open, in order;
     - `UI:VisibleRooms()`.
   - The feature registry (`UI/Features.lua`) is untouched, so `/gos open`, Settings' toggles and the
     minimap menu keep reading it.
   - `UI/Window.lua` draws the rooms on the existing tab rule and the entries on a new row under it.
     It keeps one panel per feature exactly as today. An entry with a sub-tab calls the panel's
     `SelectSub`.
   - Why this way: every screen keeps working untouched (P3, no big-bang), and each later phase only
     changes the table and the room's own screens.
4. **Hiding a hub's own sub-tab bar.**
   - A panel may expose `SetSubBarShown(bool)`. The window calls it with false when the panel is opened
     from a room entry that names a sub-tab, and true otherwise.
   - Phase 1 implements it on the Guild hub (`UI/CommunityPanel.lua`), the one hub split across rooms.
     Its sub-panels move up by the bar's height.
5. **The Salão replaces the Now tab's builder.**
   - `UI/Salao.lua` builds the Home entry from the frame-free data `UI/Agora.lua` already has:
     `NeedsMe`, `Notices`, `Activity`, `NextRaid`.
   - It adds the roster's online list and Winter Veil's counts.
   - `Agora.lua` keeps its data half and `BarText` (the 28px bar).
   - `UI/Dashboard.lua` and the Now column's drawing code are removed, since nothing draws them any more.
     The activation checklist becomes a For you line. Start raid moves under the Notice board, with the
     same stepper.
6. **Winter Veil.**
   - The `winterveil` feature keeps its panel. The window builds one panel per tab feature, so the panel
     is still built that way. The Salão's entry opens it, and so does `UI:OpenWindow("winterveil")`,
     which resolves through the room.
   - The For you line and the Chimney read `GuildOS.WinterVeil`. They never show a pair the module does
     not already show.

## Files

| File | Change |
|---|---|
| `Core/Style.lua` | one look: `Resolve`, `Available`, `Apply` |
| `UI/Rooms.lua` (new) | rooms table and lookups |
| `UI/Window.lua` | rooms on the rule, the entries row, entry selection, `OpenWindow` through rooms, ⚙ |
| `UI/CommunityPanel.lua` | `SetSubBarShown` on the Guild hub |
| `UI/Salao.lua` (new) | the Salão's Home |
| `UI/Agora.lua` | keeps its data half only |
| `UI/Dashboard.lua` | removed |
| `Core/Data.lua` | the parchment tokens: `paper`, `paperInk`, `paperSoft` |
| `UI/SettingsPanel.lua` | the game-font switch goes |
| `UI/Features.lua` | `home` builds the Salão; settings and web reached through ⚙ |
| `GuildOS.toc` | load `UI/Rooms.lua` and `UI/Salao.lua` |
| `Locales/*.lua` | room and entry names, the Salão's strings (pt-BR and en; the others fall back to enUS as today) |
| `tools/rooms.lua` (new) | the lookups and the officer gate |
| `tools/style.lua`, `tools/window-shell*.lua`, `tools/game-font.lua`, `tools/dashboard-layout.lua` | updated to the one look and the rooms |

## Tests (P2)

- `tools/rooms.lua` covers four things:
  - every tab feature lands in a room;
  - a third-party tab falls in the Salão;
  - `RoomOf("guild","calendar")` is Raids;
  - the Officers' Room is absent for a member and present for an officer, and a room with no openable
    entry is hidden.
- `tools/style.lua`: a saved `guildos` is ignored; the palette and the game's font are applied on every
  client; there is one style to choose.
- `tools/window-shell.lua`: `OpenWindow` opens the right room and entry; the hub's bar hides when opened
  from a split entry.
- `tools/salao-layout.lua` (formerly `dashboard-layout.lua`) covers the Salão in both drawings:
  - parchment cards;
  - For you (at most three lines, Winter Veil first);
  - the board's day link;
  - two columns, stacking when narrow;
  - the Chimney's stockings and words.

  The cards' own harnesses (`dashboard-chat`, `-countdown`, `-recruit`) go with `UI/Dashboard.lua`.
  `tools/raid-start-ui.lua` checks Start raid on the Salão.
- `luacheck` and the whole `tools/*.lua` suite stay green.

## Observability (P5)

- A room or the Salão that fails to build goes through `GuildOS:RunStartup` / `RecordError` as tabs do
  today. Nothing new.

## Rollback

- A revert of the PR. No saved data changes shape: `settings.window.tab` still holds a feature id.
