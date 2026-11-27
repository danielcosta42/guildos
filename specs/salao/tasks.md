# Tasks: the Salão, phase 1 (#445)

1. [x] One look in `Core/Style.lua` (Resolve, Available, Apply, PrintList). Update `tools/style.lua`,
   `tools/game-font.lua` and `tools/window-shell-forever.lua`.
2. [x] `UI/Rooms.lua` with the table and the lookups. Add `tools/rooms.lua`.
3. [x] `UI/Window.lua`:
   - rooms on the rule and the entries row;
   - entry selection, `OpenWindow` through rooms, the narrow selector;
   - the title bar's Settings button opens Settings and Web.
   Update `tools/window-shell.lua`. Depends on 2.
4. [x] Guild hub `SetSubBarShown` (`UI/CommunityPanel.lua`). Depends on 3.
5. [x] `UI/Salao.lua`: For you, Notice board, By the fire, Guild wall, Chimney, activation card.
   `home` builds it. `tools/salao-layout.lua` covers it. `UI/Dashboard.lua` is removed. Depends on 1.
6. [x] Winter Veil: the Salão entry, the For you line and the Chimney. The panel stays a feature panel,
   reached only through the room. Depends on 3 and 5.
7. [x] Locales: room, entry and Salão strings in all eleven languages (tools/locales.lua).
8. [x] `luacheck .` and every `tools/*.lua` green.
