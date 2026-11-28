## [2.2.1] - 2026-11-28

### Fixed
- Fixed lag spikes for guilds whose officers publish to guildos.me: the alliance directory the Companion brings is read a few milliseconds at a time after login and never in combat, and the roster is no longer re-read on every addon message (opening the Hall went from about 470 ms to 20 ms).
