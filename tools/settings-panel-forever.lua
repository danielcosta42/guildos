-- Settings in six sub-tabs (tools/settings-panel.lua) again, under the WoW: Forever style: the same
-- pages and every check, with the client's art, palette and font.
--
--   luajit -e 'ADDON="."' tools/settings-panel-forever.lua
ADDON = ADDON or "."
STYLE = "forever"
dofile(ADDON .. "/tools/settings-panel.lua")
