## [1.26.0] - 2026-11-16

### Added
- The core sign-up window shows one card per core with its schedule, leader, loot rule and your request state, and Cancel request is always visible.
- Raid Cores: the list shows each core's size, fill and origin (Discord or this game only); a core opens on Roster, Requests, Rule and Config, with role meters, the role picked from a list, the night's guests, and fields that say when they are saved.
- The loot popup now shows what you wear in that slot, where you stand in the loot rule (reserve, wishlist place, +1, points and entry cost) and which rule is being played.
- The master looter now works from one loot table: the boss's items and their state, the candidates in the rule's order with why each is there, the decision spelled out, and the Award button names the winner.
- Loot is now one window for every member, with Rule, Accounts, Lists and History tabs; officers edit the loot rule and points there, and every loot setting lives in that one place.
- A dropdown list now picks among several values where a button used to cycle through them, and Save buttons say when what is in the box was saved.
- Raid Cores: in a guild linked to guildos.me, a player added to a Discord core in the game is a guest of the night: kept apart from the core's members and its composition, gone when the raid session ends unless marked to stay, and shared with the other officers.
- Raid Cores: in a guild linked to guildos.me, cores are created on Discord (/core criar) and no longer in the game; a core renamed on Discord is renamed in the game on the next import, nights and points included; after 30 days with no cores from the site, officers can choose to create cores in the game again.
- Raid Cores: officers can paste the cores code from guildos.me into the website roster box (/gos roster) to receive the guild's Discord cores without the web companion; the upload now tells guildos.me which cores the game has.

### Fixed
- Undoing an award after its core was renamed now gives the points back to that core instead of the guild's own pool.
- A core can no longer be created or renamed with a | or a control character in its name, a name longer than 48 bytes, or the names constructor, prototype or __proto__.
- The Loot window's rule editor and award row now wrap at narrow window widths instead of running past the edge.
