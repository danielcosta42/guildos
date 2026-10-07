-- The one-window harness (tools/window-shell.lua) again, under the WoW: Forever style (#122): the same
-- layout and every check, with the client's art and palette. The Helpers' API did not change.
--
--   luajit -e 'ADDON="."' tools/window-shell-forever.lua
ADDON = ADDON or "."
STYLE = "forever"
dofile(ADDON .. "/tools/window-shell.lua")
