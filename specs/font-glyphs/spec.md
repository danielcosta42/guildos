# Characters the font cannot draw (issue #391)

## Why
GuildOS draws its text in IBM Plex Sans and Mono, or in the client's own font (the "game font"
setting, and always on Korean and Chinese clients). Text has to draw in both, and neither has every
geometric shape or dingbat, so such a character drew as an empty box in game:
- a "●" beside each online crafter (#389): Plex has no such glyph;
- a "✓" on a delivered wishlist item: the client's font has no such glyph.

## What
- A mark is a texture, never a character: an inline `|T...|t` or a WHITE8x8 square. The wishlist's
  delivered mark is the game's ready icon (`Interface\RaidFrame\ReadyCheck-Ready`), as the raid
  tools and audit panels already use.
- `tools/font-glyphs.lua` reads every Lua file the TOC loads, locales included and comments left
  out, and fails on any of those characters. It skips `Libs/` and `Modules/ChehulNet.lua` (shared
  verbatim, it keeps the client's font).

## Acceptance
- [x] A delivered wishlist item shows the ready icon.
- [x] The guard passes on the repository and fails on the old "✓" line.
