## [1.21.1] - 2026-11-12

### Fixed
- Each client now answers the guild's data requests at most once every two minutes (a /gos sync within 15 seconds) instead of every officer re-sending everything on every request, the heaviest traffic Guild OS made in a big guild.
- A burst of guild roster updates now costs one pass every five seconds instead of four passes per update.
- New /gos perf (also Audit > Sync) shows where Guild OS spends its time since login, with the game's own addon CPU meter where the client has one; /gos perf reset zeroes it.
