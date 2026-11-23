## [1.36.0] - 2026-11-23

### Added
- Alliance shared bans: officers can share a ban with their alliance, and see the alliance's bans as an alert when a banned player joins, whispers, is moused over or is about to be invited — never as an automatic ban.
- The guild's rules in the game: officers write them, every member reads them with /gos rules or on Guild > Rules, the welcome can point to them and a warning can name one.
- Chat alerts: stricter filters on newcomers in their first days (any link alerts, half the flood limits), with a "newcomer (day X of N)" badge for the officers.
- Anti-flood for officers: too many lines, repeats, capitals or links in guild chat become one flagged alert per person.
- Chat alerts for officers: the guild's list of words flags a line of guild chat once, with its context and a Warn button.
- Warn a member with one click: the whisper leaves on the click, the warning is filed, and the guild's next step is only suggested.
- Disciplinary record: every warning a member received, on their sheet, synced between officers only.

### Fixed
- Alliance bans: a share is no longer lost when an officer on an older version lifts the ban.
- Guild rules and newcomers: small fixes to warning templates and the newcomer period.
- Chat alerts: a slow pattern is refused instead of freezing the game, and Cyrillic, Chinese and Korean lines are read correctly.
