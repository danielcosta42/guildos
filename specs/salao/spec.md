# The Salão, phase 1: one look, rooms, and the Salão as the first screen (#445, epic #444)

Decided with the maintainer on 2026-11-25. Approved prototype (every screen, both roles, the three clients):
https://claude.ai/artifact/WecMZMDtt2qSfXJyqCuDCq

## 1. Problem

Players report that the addon looks "technological" and out of place in the game:
- a terminal font (IBM Plex Mono) and upper-case tracked labels;
- a flat purple-black background;
- fourteen tabs, an officer's sixteen;
- a first screen that is a column of numbers.

The game is stone, bronze, wood and parchment, and so is the rest of the default UI.

## 2. Goal

Opening Guild OS should feel like opening one more window of the game. The first screen is a place,
the Salão, which answers in three seconds what is on tonight, who is home and what this player still
has to do. The rest of the addon is a few rooms with names from the game, not a row of tabs.

Phase 1 changes the look, the navigation and the first screen. The screens inside the rooms keep their
content; each room is redrawn in its own phase (epic #444).

## 3. User stories and acceptance criteria

### 3.1 One look
- The flat "GuildOS" style and the style picker are gone; every client draws the same look.
- Where the client has WoW: Forever's art, the frames are the client's own (`Style.FOREVER`).
- Everywhere else, the look keeps the same stone, bronze and parchment palette (`Style.FOREVER_PALETTE`).
- Every text uses the client's font (`STANDARD_TEXT_FONT`). IBM Plex is no longer loaded.
- A saved `GuildOSDB.style = "guildos"` is ignored without a message.
- `/gos style` lists the one look.

### 3.2 Rooms
- The bar under the title holds the rooms, left to right:
  - Salão, Raids, Members, Loot, Workshop, Chronicle (localized names);
  - the Officers' Room, only for officers.
- A room shows only while at least one of its entries may open (present on this client, switched on,
  started, the rank allows it).
- Under the rooms, a second row holds the open room's entries. A room with a single entry draws no row.
  Entries that do not fit fold into "»n", as the rooms do, so none is lost on a narrow window.
- Narrowed under 520px the window shows the Salão's Home. Widened again, it returns to the room, entry and
  sub-tab that were open.
- An officer who is demoted while the Officers' Room is open leaves it at once.
- Phase 1 rooms and entries, in order:

| Room | Entries (feature › sub-tab) |
|---|---|
| Salão | Home (`home`), Notices (`guild` › bulletin), Rules (`guild` › rules), Call to Arms (`guild` › cta), Polls (`guild` › polls), Chat (`guild` › chat), Alliance (`alliance`), Secret Santa (`winterveil`) |
| Raids | Calendar (`guild` › calendar), Raids (`raids`), Groups (`groups`) |
| Members | Members (`roster`) |
| Loot | Loot (`loot`) |
| Workshop | Crafts (`recipes`), Guild bank (`bank`) |
| Chronicle | Achievements (`guild` › achievements), Journal (`guild` › journal), Activity (`guild` › activity) |
| Officers' Room | Leadership (`management`), Recruitment (`recruitment`) |

- A **Settings** button in the title bar (beside Search and Sync) opens Settings, and Web is one of its
  entries. Settings and Web are reached only from there. A text button, not ⚙: the game's font has no
  such glyph. When the bar narrows it goes last, after the sync time, Search and Sync.
- An entry that names a sub-tab opens that sub-tab. When the panel lets a room hide its own sub-tab bar
  (the Guild hub in phase 1), the room hides it, so a screen never shows two rows of the same tabs.
- A tab another addon registers through `UI:RegisterFeature` with `tab = true`, and no room names, is an
  entry of the Salão.
- `UI:OpenWindow(id, sub, filter)` keeps working unchanged: it opens the room that holds `id` (and
  `sub`) and selects that entry.
  - The slash commands, the minimap menu and every deep link go through it.
  - `/gos open guild calendar` lands on Raids › Calendar.
- The Officers' Room is never shown to a non-officer, by click, deep link or command. The existing
  `officerOnly` gate holds.
- The narrow bands keep working: under 520px the selector lists the rooms' entries.

### 3.3 The Salão (replaces the Now tab)
The `home` feature becomes the Salão's Home entry. It has four parts, in two columns that stack under
the wide band.

1. **For you.** At most three lines, each with one action that opens the screen that owns it.
   - They come from `Agora:NeedsMe()`: an unanswered raid, the officer's trials, inactives, promotions
     and applicants.
   - While a Winter Veil event is on: "You drew X" with Wrap (before the opening), or "Your globe
     arrived" with Open (after it). This line goes first.
   - With nothing to do: "All caught up."
2. **Notice board.**
   - The next three events from the calendar (`Calendar:GetUpcoming`), each with its time and this
     player's answer when there is one; a click opens Raids › Calendar on that day.
   - The newest bulletin notice under them (`Agora:Notices(1)`).
3. **By the fire.** Guildmates online now (up to 8, then "+N"), each with class colour and zone. A
   click opens the member's menu (whisper, invite, open their sheet).
4. **Guild wall.** The last five lines of `Agora:Activity`, each opening the screen that owns it.

- On WoW: Forever, until a week after the raids open, a **raids countdown** card heads the right column.
  It comes from `Readiness:Countdown` (#207): the days left, each core at the level cap, and the guild.
- While a Winter Veil event is on, a **Chimney** card above By the fire shows one stocking per entrant,
  filled for each one who wrapped (`counts.entrants`, `counts.wrapped`).
- After the opening it reads "The Chimney is lit" with the count of opened globes.
- It never names who wrapped: that stays the officers' (specs/winter-veil).
- The Now column and its cards (`UI/Dashboard.lua`) are removed.
  - Their content is still reachable from the rooms: readiness (Raids › Raids › Audit), recruitment
    (Officers' Room), loot (Loot), guild chat (Salão › Chat).
  - The Forever activation checklist becomes a For you line for the GM and officers ("Set up Guild OS for
    your guild: N of 5 steps", opening Web) while `Activation:ShouldShow` says so.
  - Start raid (#400) moves under the Notice board. It is the same stepper as Web's, shown while this
    player may lead the invites of the site's raid in its window, with the raid's name over it.

### 3.4 Winter Veil inside the Salão
- The event has no top-level tab any more. While the site sends this year's event, Secret Santa is an
  entry of the Salão. It opens the existing Winter Veil panel, with its own sub-views (my secret friend,
  collection, the chain, organize). The `winterveil` feature stays a panel of the window; only the room
  decides where it is reached.
- The Salão's For you line and its Chimney card are the event's front door.
- Everything private stays as specs/winter-veil says. The addon only shows and records, and never shows
  a pair before the opening.

## 4. Out of scope (later phases of #444)

- Redrawing the screens inside Raids, Members, Loot, Workshop, Chronicle and the Officers' Room, and
  merging their inner sub-tab bars into the room's row.
- Wood and parchment textures as TGA art.
- The new onboarding wizard.
- The systems audit.

## 5. Risks

- **Deep links.** Every entry point goes through `UI:OpenWindow`, so the room lookup is the one place
  to get right. `tools/window-shell.lua` covers it.
- **Third-party tabs.** They fall back to the Salão, so they stay reachable.
- **Flat style users.** They lose their style. The maintainer decided this.

---

# Phase 2: one row only (#447)

After phase 1, several screens still drew their own row of sub-tabs under the room's row: Raids, Loot,
Bank, Leadership, Recruitment and Settings. Phase 2 turns those sub-tabs into the rooms' own entries, so a
screen never shows two rows of tabs.

## Entries

| Room | Entries |
|---|---|
| Raids | Calendar, Sessions, Raiders, Cores (officers), Audit, Raid Tools, Groups, Core Sign-up |
| Loot | Rule, Accounts (while the Points module is there), Lists (while Wishlist or SoftRes is), History |
| Workshop | Crafts, Bank, Tabs, Ledger, Needs, Requests, Cleanup (while GuildBankCleanup is there) |
| Officers' Room | a side bar in four groups (below) |
| Settings | Profile, Interface, Chat and alerts, Modules, Guild rules, Data and support, Web |

The Officers' Room groups:
- **Recruitment:** Recruiting, Scanner, Trials, Engagement;
- **Members:** Suggestions, Ranks, Inactivity, Bulk actions, Presets, Without GuildOS, Notes and marks;
- **Moderation:** Chat alerts, Alert rules, Ban List, Audit Log;
- **Guild:** MOTD / Info.

## Rules

- **A screen's own bar hides.** Each of those screens lets a room hide its own sub-tab bar
  (`UI:CollapsibleSubBar` in UI/Helpers.lua, which writes `SetSubBarShown`). Its panels then start where
  the bar was.
  - Groups and the Alliance keep their own row in this phase. There the sub-tabs filter the content
    (activities; bulletin and chat), not separate screens.
- **Core Sign-up is an action, not a screen.** It was a button on the Raids bar. It opens the sign-up
  window and leaves the screen on show as it was.
- **Three new kinds of entry.**
  - `officer`: an officers' entry in a room everybody has. A member's Raids has no Cores.
  - `cond`: the entry needs its module to be there.
  - `group`: the entry's heading in a side room.
- **The Officers' Room draws a side bar.** It has sixteen entries, so it draws a column in groups left of
  the content instead of the row. Narrowed into the watch band, it falls back to the folding row.
- **A feature opened by name alone** lands on the sub-tab it opened on before (`UI.ROOM_PREFERRED`):
  - Raids: Sessions;
  - Loot: Rule;
  - Bank: Inventory;
  - Leadership: Ranks;
  - Recruitment: Recruiting;
  - Settings: Profile;
  - Guild: Achievements on WoW: Forever, else the calendar.
- **An action is never where a screen opens.** `UI:RoomOf` skips `run` entries.
