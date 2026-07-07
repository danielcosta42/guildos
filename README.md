# ![Guild OS](https://img.shields.io/badge/Guild%20OS-Guild%20Manager-blueviolet?style=for-the-badge) 

### Premium Guild Management Addon for WoW TBC Anniversary

> Made with care by **Chehul** 🛡️

Guild OS replaces the default guild frame with a modern, feature-rich management hub that automatically collects and shares gear, professions, attunements, TMB wishlists, raid attendance, loot history and stats across your guild — no inspection required.

> **Client:** WoW TBC Anniversary (Interface 20506)

---

## Features

### Guild Roster
- **Full guild roster** with sortable columns: Name, Level, Class, Race, Item Level, Professions, Attunements, Attendance%, Last Seen
- **Search** by name, class, zone or rank
- **Online/Offline toggle** with offline members shown in grayscale
- **Hover tooltips** with detailed character info
- **Click any member** to open their full inspection panel
- **Stats bar** showing total members, online count, and how many have Guild OS installed

### Member Detail Panel
- Full equipment inspection (17 gear slots) with quality-colored item names and tier-colored item levels
- Profession list with progress bars and rank display
- Character stats: HP, Mana, STR, AGI, STA, INT, SPI
- Raid attunement progress with per-quest tracking and visual progress bars
- **Account-wide attunements** — attunements completed on any linked alt are shown as complete with a `(conta: NomeDoChar)` indicator
- **Linked Characters** section (officer only) — link/unlink alts to share attunement data across a player's entire account group

### Attunement Tracker
Tracks quest-based attunement progress for all TBC raids:

| Raid | Tier |
|---|---|
| Karazhan | T4 |
| Gruul's Lair | T4 |
| Magtheridon's Lair | T4 |
| Serpentshrine Cavern | T5 |
| Tempest Keep: The Eye | T5 |
| Hyjal Summit | T6 |
| Black Temple | T6 |
| Sunwell Plateau | T6.5 |

Also tracks Heroic dungeon key reputation requirements (Honor Hold/Thrallmar, Cenarion Expedition, Lower City, Sha'tar, Keepers of Time).

**Account-wide propagation:** Officers can link a player's alts so that attunements completed on any character in the group are reflected across all of them — matching how Blizzard handles account-wide attunements on TBC Anniversary.

### TMB Integration (That's My BiS)
- Import TMB CSV exports with wishlist, prio, and received loot data
- Tooltip integration — hover any item to see who has it on their wishlist
- Syncs imported TMB data between officers via addon comms
- Dedicated TMB Loot tab for browsing all imported data

### Guild Recipe Browser
- Searchable browser for all recipes known across the guild
- **Icon-only profession filter tabs** — compact tab bar with one icon per crafting profession; full name shown on hover tooltip
- Gathering professions (Herbalism, Mining, Skinning, Fishing) are filtered out — only crafting professions shown

### Raid Tracker
- Automatically detects when you enter a raid and tracks full sessions (start/end, boss encounters, player snapshots)
- Attendance scoring with penalty system: 100% base, −10% arrived late, −10% left early, −10% missing consumables
- View recent sessions and per-member attendance in the Raids tab

### Consumable Checker
- Scans all raid members for expected TBC consumable buffs
- Checks 5 categories: Flask, Food, Weapon Buff, Battle Elixir, Guardian Elixir
- Reports which categories each player is missing
- Integrates with attendance scoring

### Loot Tracker
- Automatically records every Rare+ item looted in raids and dungeons
- Stores item link, recipient, timestamp, raid name, and quantity
- Browse full loot history in the Loot tab
- Keeps up to 500 entries

### Officer Notes
- Write private notes and apply quick-tags (Role, Priority, Status) per guild member
- Notes are synced between officers in real time via addon comms

### Trial Tracker (Officer Only)
- Track trial/recruit members with configurable trial periods (default 30 days)
- Records start date, sponsor, status (trial/approved/denied/expired), and evaluation notes
- Auto-expires overdue trials and alerts officers

### Officer Rank Configuration (Officer Only)
- Configure which guild ranks are considered "officers" directly from the Settings tab
- Checkboxes for each guild rank — GM is always locked as officer
- Changes take effect immediately; only current officers can modify this setting
- Synced across all addon instances in the guild

### Guild-Wide Data Sync
- Automatically shares your gear, professions, attunements and stats with guildmates who have Guild OS installed
- Compressed and chunked communication protocol (LibSerialize + LibDeflate)
- Periodic sync every 5 minutes + manual sync button
- No manual inspection needed — data flows automatically

### Recruitment System (Officer Only)
- **Auto-recruit popup** — a notification appears on a configurable interval; click it to send your recruitment message to chat channels (LookingForGroup, Trade, etc.)
- **Send Now button** in the Recruitment tab for instant posting
- **Welcome message** — automatically posts a greeting in guild chat when a new member joins, with customizable message and Discord link
- **Guild invite** via `/guildos recruit invite <Player>`
- Full configuration UI in the Recruitment tab: message, interval, channels, welcome text, Discord link

### Tab System
| Tab | Access |
|---|---|
| Roster | All members |
| TMB Loot | All members |
| Raids | All members |
| Loot | All members |
| Trials | Officers only |
| Recruitment | Officers only |

### Guild Frame Hook
Pressing **J** (or however you open the guild frame) opens Guild OS instead of the default Blizzard guild panel.

---

## Slash Commands

| Command | Description |
|---|---|
| `/guildos` or `/gos` | Toggle the roster window |
| `/guildos scan` | Re-collect your local character data |
| `/guildos sync` | Broadcast your data to the guild |
| `/guildos reset` | Wipe saved data and reload |

> **Legacy commands** `/brutus` and `/br` continue to work as aliases.

### Recruitment Commands (Officer+)

| Command | Description |
|---|---|
| `/guildos recruit on/off` | Start/stop auto-recruit popup |
| `/guildos recruit status` | Show recruitment status |
| `/guildos recruit msg <text>` | Set recruitment message |
| `/guildos recruit interval <sec>` | Set popup interval (min 60s) |
| `/guildos recruit channel add/remove/list <name>` | Manage channels |
| `/guildos recruit welcome on/off` | Toggle welcome message |
| `/guildos recruit welcome msg <text>` | Set welcome message |
| `/guildos recruit discord <link>` | Set Discord link |
| `/guildos recruit invite <Player>` | Send guild invite |

---

## Installation

1. Download and extract into your `Interface/AddOns/` folder
2. The folder must be named `GuildOS`
3. Restart WoW or type `/reload`
4. Press **J** to open Guild OS or type `/guildos`

> **Upgrading from BRutus?** Your saved data migrates automatically on first load. The old `BRutusDB` is preserved alongside the new `GuildOSDB`.

---

## Libraries

- [LibStub](https://www.wowace.com/projects/libstub)
- [CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler)
- [LibSerialize](https://github.com/rossnichols/LibSerialize)
- [LibDeflate](https://github.com/SafeteeWoW/LibDeflate)
- [ChatThrottleLib](https://www.wowace.com/projects/chatthrottlelib)

---

## Notes

- **SendChatMessage to channels** (LookingForGroup, Trade, etc.) requires a hardware click due to Blizzard restrictions. Guild OS handles this by showing a clickable popup notification instead of sending automatically.
- Officer permission is determined by configurable guild rank threshold (default: rank ≤ 2). Adjustable in the Settings tab by current officers.
- Data is stored per-guild in `GuildOSDB` SavedVariables (isolated per guild name+realm). Legacy `BRutusDB` is preserved and migrated automatically.
- Account-wide attunements require officers to manually link a player's alt characters via the Member Detail panel.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

Third-party libraries are included under their own respective licenses (MIT, zlib, Public Domain).

---

## Contributing

Bug reports and feature requests are welcome! Please use the [GitHub Issues](https://github.com/danielcosta42/GuildOS/issues) page.

---

## Support

If Guild OS has been useful to your guild and you'd like to help keep it maintained, consider buying me a coffee ☕

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-0070BA?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=daniel.cfdutra13%40gmail.com&no_recurring=0&currency_code=USD)
