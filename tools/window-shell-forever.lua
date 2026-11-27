-- The one-window harness (tools/window-shell.lua) again, on a WoW: Forever client with its atlases (#122): the same
-- layout and every check: since the Salão's phase 3 (#449) no atlas changes the look, so nothing differs.
--
--   luajit -e 'ADDON="."' tools/window-shell-forever.lua
ADDON = ADDON or "."
STYLE = "forever"
dofile(ADDON .. "/tools/window-shell.lua")
