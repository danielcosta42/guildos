# Guild OS Changelog

All notable changes to this project will be documented in this file.

## [0.19.1] - 2026-07-06

### Changed
- Shared cross-addon presence (ChehulNet) bumped to v3: the HELLO now carries this
  character's **layer** (`mapID:zoneUID`), detected via a built-in minimal detector, so
  GuildOS users are visible by layer across the whole Chehul mesh (PartyLens's occupancy
  map, Circle, etc.) — not just by class/level. Also answers the `ChehulPing` RTT probe now,
  so the network monitor can measure round-trip to GuildOS users. Ship-identical shared file.

## [0.19.0] - 2026-07-06

### Added
- gossip-relay ads + personalization + recruitment-tab composer
- RecruitBeacon — guild recruitment matching over the mesh

### Fixed
- boot the addon for guildless players (mesh + recruitment)

## [0.18.0] - 2026-07-06

### Added
- Craft Finder UI for the realm-wide crafting network

### Other
- Shared mesh -> LibChehulMesh v3 (AceComm-3.0 + ChatThrottleLib; realm bus now YELL). Identical file across the Chehul family.


## [0.17.0] - 2026-07-05

### Added
- CraftNet — realm-wide "who can craft this?" over the mesh


## [0.16.0] - 2026-07-05

### Added
- light up ChehulNet presence — advertise version, consume peers


## [0.15.1] - 2026-07-05

### Fixed
- make Auto-announce toggle and Loot Master kill-switch actually work


## [0.15.0] - 2026-07-05

### Added
- adopt shared LibChehulMesh transport (realm-wide ChehulNet presence)


## [0.14.0] - 2026-07-05

### Added
- join the ChehulNet cross-addon presence mesh


## [0.13.1] - 2026-07-05

### Fixed
- suppress MS/OS popup during native group loot


## [0.13.0] - 2026-07-02

### Added
- drop General and LocalDefense channel toggles


## [0.12.0] - 2026-07-02

### Added
- add GuildRecruitment channel toggle


## [0.11.3] - 2026-07-02

### Fixed
- reliable first-open + periodic member-data sync


## [0.11.2] - 2026-07-02

### Fixed
- remove channel list from recruit popup label


## [0.11.1] - 2026-07-02

### Fixed
- deterministic welcome tiebreak to prevent duplicate messages


## [0.11.0] - 2026-07-02

### Added
- multi-select channel toggles in officer panel


## [0.10.1] - 2026-07-02

### Changed
- remove class needs selector


## [0.10.0] - 2026-07-02

### Added
- all members can spam recruitment messages


## [0.9.0] - 2026-07-02

### Added
- expose class needs to all members


## [0.8.0] - 2026-07-01

### Added
- SoftRes import from softres.it + version mismatch fix

### Fixed
- prefix unused sender arg with underscore in CoreManager


## [0.7.0] - 2026-06-22

### Added
- global Search button in the main window header
- Guild hub + DKP main tabs (move features into the interface)
- accent color presets (C4)
- global search / command palette (C5)
- milestones & guild anniversaries (B3)
- guild polls / voting (B1)
- officer bulletin board (B2)
- backup/restore the guild DB (C2)

### Fixed
- remove hardcoded Discord link default


## [0.6.0] - 2026-06-21

### Added
- login digest — "since your last login" catch-up (A5)
- default officer threshold to rank 1; officer-only onboarding
- credit Chehul in the Settings > About section
- category sub-tabs + fill config gaps
- surface only the active loot system's UI
- honor the selected loot system (rolls/TMB/wishlist/DKP)
- UI access for all features + loot-system settings (officer)
- loot equity analytics (A3)
- DKP / EPGP / Loot Council economy (S1)
- CSV / TSV / Discord export + import parser (A6)
- "Is the raid ready?" rollup (S4)
- SyncService v2 — versioned envelope, dedup, revision, ACK

### Fixed
- clear FontString/texture regions on settings re-render


## [0.5.0] - 2026-06-20

### Added
- explicit Save buttons on text fields; silence keybind warning
- commercial polish — onboarding, error resilience, prune, keybinds, about (v0.4.0)

### Changed
- replace user-facing "BRutus"/"/brutus" with "Guild OS"/"/guildos"


## [0.4.0] - 2026-06-19

### Added
- audit suite, raid tools, loot equity, minimap & QoL (v0.3.0)


## [0.3.0] - 2026-06-18

### Added
- guild leadership suite + full i18n (EN/PT/ES/DE/FR)


## [0.2.1] - 2026-06-16

### Fixed
- allow clearing the class filter


## [0.2.0] - 2026-06-16

### Added
- obsidian theme, roster dashboard, and raid HUD/loot fixes


## [0.1.1] - 2026-06-16

### Fixed
- reconnect non-functional control and drop dead event registrations
- correct addon flaws found in full review


## [0.1.0] - 2026-05-20

### Added
- rename and migrate Guild OS, update documentation and commands
- enhance Master Looter checks for group and raid scenarios
- update roll popup visibility to show in groups instead of just raids
- restrict roll popup and bag roll functionality to raid only
- update Loot tab visibility to always show for officers
- enhance Loot Master and Roster Frame with conditional tab visibility and raid checks
- Add complete function catalog and Lua best practices documentation
- add addon version tracking to broadcast data and roster UI for version comparison
- update welcome message functionality to post in guild chat and add priority handling for message broadcasting
- modify HandleRequest to broadcast data to GUILD instead of WHISPER to prevent spam
- add support section to README with donation link
- update publish workflow to include Wago and clarify package publishing
- optimize memory usage by reusing member list table in roster frame
- add GetItemCount to read_globals for enhanced item tracking
- update attunement tracking logic and clarify account-wide limitations
- add attunement status and debug commands to chat interface
- refactor duplicate session merging logic for improved clarity
- update attunement display to show only game-verified data without alt-propagation
- enhance encounter tracking and deduplication logic in raid sessions
- improve session merging logic with debounce handling for incoming raid broadcasts
- migrate wishlist data structure to per-character storage and update related functionality
- add manual close flags for HUD and consumable popup to improve user experience
- debounce wishlist panel updates on item info received to improve performance
- enhance session merging by deduplicating encounters and normalizing snapshot data
- add guild-only filter to recent sessions retrieval in RaidTracker
- enhance wishlist functionality with item delivery tracking and improved UI display
- implement session deletion tracking and enhance loot award handling
- enhance OnEnterWorld to handle initial login and UI reload scenarios
- add RAID_DELETE message type and officer verification for raid session deletion
- add event listener to refresh wishlist frame on item info received
- restrict wishlist access and display to officers only during testing
- Implement Wishlist System for per-character item tracking and guild-wide synchronization
- add zone column to roster UI and update frame width
- add additional WoW API read globals for talent inspection functionality
- implement talent data collection and viewer for player specs
- add SpecChecker module to collect and display talent spec data
- Add functionality to record received loot, remove entries, and export as CSV
- update settings panel to mark certain features as officer-only
- add new WoW API globals for spell texture and invite functions
- add RaidHUD for tracking raid cooldowns and consumable checks
- enhance raid attendance tracking for 25-man raids and update UI components
- add welcome message claim functionality for officers
- implement full sync for officer data including raid attendance and officer notes
- enhance account-wide attunement support and improve UI for linked characters in README and CURSEFORGE
- implement alt/main linking for account-wide attunement propagation and enhance member detail UI
- add officer rank configuration panel and integrate WoW guild control API for rank management
- add support for new profession 'Poisons' and enhance profession checks in RecipeTracker
- enhance welcome message handling for new guild members with roster tracking
- enhance item and spell crafter indexing for improved tooltip information
- migrate data storage from BRutusDB to BRutus.db for improved modularity
- exclude gathering professions from stale profession checks and recipe listings
- improve recipe deduplication by skipping name-only entries without ID matches
- enhance tooltip display for recipe items and spells in the Recipes panel
- enrich recipe data by merging spellIds and enhance gem tooltips in member detail
- enhance recipe scanning to extract enchant IDs from item links and merge duplicate entries
- add item crafter index and tooltip enhancements for recipe visibility
- enhance whisper functionality to include item link in messages
- restrict officer-only module initialization and settings visibility
- enhance guild invitation tracking and welcome messaging
- enhance trial data broadcasting and handling for officers
- enhance profession handling and item display across various modules
- group crafters in recipe index and update online status display
- Implement profession freshness check and reminder system
- enhance WoW API integration and improve function parameters in LootMaster and UI panels
- implement publish workflow for CurseForge and trigger from release workflow
- update release workflow to include packaging and publishing to CurseForge
- update release workflow to remove re-checkout step and add publish workflow for CurseForge
- add re-checkout step for tagged commit in release workflow
- add right-click context menu for roster members with various actions

### Fixed
- correctly handle checkbox state in settings panel
- update isGuildRaid checks to include legacy session data
- streamline attendance migration check for old format
- correct registration of Mining profession to include the correct parameters
- remove redundant LibSerialize initialization in BroadcastAllNotes and HandleAllIncoming functions
- correct reference to guildKey in reset command for proper database reset functionality
- correct formatting in login message and streamline playerKey assignments in member detail population
- standardize text formatting and improve UI element labels across multiple files
- update descriptions and labels for clarity in CURSEFORGE.md, README.md, and RecruitmentSystem.lua
- update parameter name in ShowMemberContextMenu for consistency
- update parameter names in CreateTMBPanel and RenderItemRows for consistency
- format update TOC version step for better readability

### Changed
- simplify conditionals for guild-only session filtering and improve variable naming in session merging
- update variable naming for clarity and remove unused attendance export button
- update attendance merging logic to support new nested format
- remove unused variables in PopulateDetail function for improved clarity
- remove unused variables and improve code clarity in LootMaster and FeaturePanels
- remove unused ENCHANTABLE_SLOTS definition from MemberDetail.lua
- release workflow to include linting with Luacheck and version bumping logic

### Other
- Add Spec Checker, Trial Tracker, and Wishlist System modules
- Refactor attendance tracking and loot distribution features
- Add Recipe Tracker and Recipes Panel for guild tradeskill management
- Add Loot Tracker, Officer Notes, Raid Tracker, Trial Tracker, and UI Panels
- Add TMBIntegration.lua for That's My BiS integration
- Update release workflow to include version tagging and push to CurseForge
- Remove unused local variables in CreateRecruitmentPanel function
- Update luacheck ignore codes in CreateRecruitmentPanel function
- Refactor code for improved clarity and performance; update luacheck configuration and remove unnecessary externals
- Update luacheck configuration and correct Curse Project ID in toc file
- Update project metadata, add issue templates, and enhance documentation
- Implement recruitment system popups and manual send button; update documentation
- Initial commit


## [1.42.1] - 2026-05-05

### Fixed
- correctly handle checkbox state in settings panel


## [1.42.0] - 2026-05-04

### Added
- enhance Master Looter checks for group and raid scenarios


## [1.41.0] - 2026-05-03

### Added
- update roll popup visibility to show in groups instead of just raids


## [1.40.0] - 2026-05-03

### Added
- restrict roll popup and bag roll functionality to raid only


## [1.39.0] - 2026-05-03

### Added
- update Loot tab visibility to always show for officers


## [1.38.0] - 2026-05-03

### Added
- enhance Loot Master and Roster Frame with conditional tab visibility and raid checks


## [1.37.1] - 2026-05-03

### Other
- Add Spec Checker, Trial Tracker, and Wishlist System modules


## [1.37.0] - 2026-05-01

### Added
- Add complete function catalog and Lua best practices documentation


## [1.36.0] - 2026-04-27

### Added
- add addon version tracking to broadcast data and roster UI for version comparison
- update welcome message functionality to post in guild chat and add priority handling for message broadcasting


## [1.35.0] - 2026-04-26

### Added
- modify HandleRequest to broadcast data to GUILD instead of WHISPER to prevent spam


## [1.34.0] - 2026-04-26

### Added
- add support section to README with donation link
- update publish workflow to include Wago and clarify package publishing
- optimize memory usage by reusing member list table in roster frame


## [1.33.0] - 2026-04-26

### Added
- add GetItemCount to read_globals for enhanced item tracking
- update attunement tracking logic and clarify account-wide limitations
- add attunement status and debug commands to chat interface


## [1.32.0] - 2026-04-26

### Added
- refactor duplicate session merging logic for improved clarity
- update attunement display to show only game-verified data without alt-propagation
- enhance encounter tracking and deduplication logic in raid sessions
- improve session merging logic with debounce handling for incoming raid broadcasts


## [1.31.0] - 2026-04-26

### Added
- migrate wishlist data structure to per-character storage and update related functionality


## [1.30.0] - 2026-04-26

### Added
- add manual close flags for HUD and consumable popup to improve user experience


## [1.29.0] - 2026-04-26

### Added
- debounce wishlist panel updates on item info received to improve performance


## [1.28.0] - 2026-04-26

### Added
- enhance session merging by deduplicating encounters and normalizing snapshot data
- add guild-only filter to recent sessions retrieval in RaidTracker
- enhance wishlist functionality with item delivery tracking and improved UI display
- implement session deletion tracking and enhance loot award handling

### Changed
- simplify conditionals for guild-only session filtering and improve variable naming in session merging
- update variable naming for clarity and remove unused attendance export button


## [1.27.0] - 2026-04-26

### Added
- enhance OnEnterWorld to handle initial login and UI reload scenarios


## [1.26.0] - 2026-04-26

### Added
- add RAID_DELETE message type and officer verification for raid session deletion


## [1.25.1] - 2026-04-26

### Fixed
- update isGuildRaid checks to include legacy session data


## [1.25.0] - 2026-04-26

### Added
- add event listener to refresh wishlist frame on item info received


## [1.24.1] - 2026-04-26

### Changed
- update attendance merging logic to support new nested format


## [1.24.0] - 2026-04-26

### Added
- restrict wishlist access and display to officers only during testing


## [1.23.0] - 2026-04-26

### Added
- Implement Wishlist System for per-character item tracking and guild-wide synchronization

### Fixed
- streamline attendance migration check for old format


## [1.22.0] - 2026-04-26

### Added
- add zone column to roster UI and update frame width

### Fixed
- correct registration of Mining profession to include the correct parameters

### Other
- Refactor attendance tracking and loot distribution features


## [1.21.0] - 2026-04-25

### Added
- add additional WoW API read globals for talent inspection functionality
- implement talent data collection and viewer for player specs
- add SpecChecker module to collect and display talent spec data

### Changed
- remove unused variables in PopulateDetail function for improved clarity


## [1.20.0] - 2026-04-24

### Added
- Add functionality to record received loot, remove entries, and export as CSV

### Changed
- remove unused variables and improve code clarity in LootMaster and FeaturePanels


## [1.19.0] - 2026-04-23

### Added
- update settings panel to mark certain features as officer-only


## [1.18.0] - 2026-04-23

### Added
- add new WoW API globals for spell texture and invite functions
- add RaidHUD for tracking raid cooldowns and consumable checks
- enhance raid attendance tracking for 25-man raids and update UI components


## [1.17.0] - 2026-04-21

### Added
- add welcome message claim functionality for officers


## [1.16.0] - 2026-04-21

### Added
- implement full sync for officer data including raid attendance and officer notes

### Fixed
- remove redundant LibSerialize initialization in BroadcastAllNotes and HandleAllIncoming functions


## [1.15.0] - 2026-04-21

### Added
- enhance account-wide attunement support and improve UI for linked characters in README and CURSEFORGE
- implement alt/main linking for account-wide attunement propagation and enhance member detail UI
- add officer rank configuration panel and integrate WoW guild control API for rank management
- add support for new profession 'Poisons' and enhance profession checks in RecipeTracker
- enhance welcome message handling for new guild members with roster tracking
- enhance item and spell crafter indexing for improved tooltip information
- migrate data storage from BRutusDB to BRutus.db for improved modularity

### Fixed
- correct reference to guildKey in reset command for proper database reset functionality
- correct formatting in login message and streamline playerKey assignments in member detail population


## [1.14.0] - 2026-04-20

### Added
- exclude gathering professions from stale profession checks and recipe listings


## [1.13.0] - 2026-04-19

### Added
- improve recipe deduplication by skipping name-only entries without ID matches
- enhance tooltip display for recipe items and spells in the Recipes panel
- enrich recipe data by merging spellIds and enhance gem tooltips in member detail
- enhance recipe scanning to extract enchant IDs from item links and merge duplicate entries


## [1.12.0] - 2026-04-19

### Added
- add item crafter index and tooltip enhancements for recipe visibility
- enhance whisper functionality to include item link in messages
- restrict officer-only module initialization and settings visibility


## [1.11.0] - 2026-04-19

### Added
- enhance guild invitation tracking and welcome messaging


## [1.10.0] - 2026-04-19

### Added
- enhance trial data broadcasting and handling for officers


## [1.9.0] - 2026-04-19

### Added
- enhance profession handling and item display across various modules


## [1.8.0] - 2026-04-19

### Added
- group crafters in recipe index and update online status display


## [1.7.0] - 2026-04-19

### Added
- Implement profession freshness check and reminder system

### Changed
- remove unused ENCHANTABLE_SLOTS definition from MemberDetail.lua


## [1.6.0] - 2026-04-19

### Added
- enhance WoW API integration and improve function parameters in LootMaster and UI panels

### Other
- Add Recipe Tracker and Recipes Panel for guild tradeskill management


## [1.0.0] - 2026-04-18

### Added
- Full guild roster with sortable columns (name, level, class, race, item level, professions, attunements, last seen)
- Member detail panel with equipment inspection, profession progress bars, and raid attunement tracking
- Attunement tracking for all TBC raids (Karazhan, Gruul, Magtheridon, SSC, TK, Hyjal, BT, Sunwell) and heroic dungeon keys
- Compact attunement summary with color-coded progress and tooltip details
- Guild-wide data synchronization via addon messaging with compression (LibDeflate + LibSerialize)
- Chunked message protocol for large data transfers (230-byte chunks)
- Recruitment system with popup-based channel messaging (compliant with Blizzard hardware event requirements)
- Automatic welcome whisper for new guild members with customizable message and Discord link
- Tab-based UI: Roster tab (all members) and Recruitment tab (officers only)
- Officer permission system (rank-based + CanGuildInvite fallback)
- Search and filter functionality for the guild roster
- Offline member display with grayscale styling
- Integration with default guild frame (J key hook)
- Slash commands: `/brutus` with subcommands for roster, sync, recruitment management
